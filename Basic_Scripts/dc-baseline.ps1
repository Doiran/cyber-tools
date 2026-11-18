#Requires -RunAsAdministrator
<#
  CCDC DC defender: baseline drift + unapproved-account detection, and Sysmon->Wazuh setup.
  Modes:
    -Mode Baseline   Snapshot users/admins/SPNs/preauth/tasks/services/procs/autoruns to C:\ccdc\bl
    -Mode Check      Diff against baseline + flag enabled domain users not on the approved list
    -Mode Sysmon     Install/update Sysmon with a standard config and wire it into the Wazuh agent
    -Mode RollPasswords  Reset every enabled domain user off the default password
#>
param(
  [ValidateSet('Baseline','Check','Sysmon','RollPasswords')][string]$Mode = 'Check',
  [string]$SysmonBin,                 # path to sysmon64.exe; auto-found or downloaded if omitted
  [string]$SysmonConfig,              # path to a sysmon config xml; downloaded if omitted
  [string]$ConfigUrl = 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml',
  # --- RollPasswords ---
  [string[]]$ScoredAccounts = @(),    # accounts the scoreboard logs in as: rolled + PRINTED so you can update the scoreboard
  [string]$NewPassword,               # fixed password for SCORED accounts (one to type into the scoreboard); random if omitted
  [string[]]$ExcludeAccounts = @(),   # never touch these (your break-glass account, etc.)
  [switch]$IncludeServiceAccounts     # also roll service accounts (svc_* / SPN holders) - WILL break the service until you fix it
)

$ErrorActionPreference = 'Continue'
$Dir = 'C:\ccdc\bl'
$AR  = 'C:\Tools\Sysinternals Suite\autorunsc64.exe'
New-Item -ItemType Directory -Path $Dir -Force | Out-Null

# --- approved accounts (from the briefing) + default AD/Windows accounts -------
$Approved = @(
  'ftruman','htruman','abrennan','lmoran','bbriggs','cbraxford','dcooper','jholcomb',
  'hawk2hill','lpalmer','ljacoby','whayward','broundtree','lshelvy','jim','arosenfield',
  'ahorne','emt','doctor','nurse','svc_ehr',
  'Administrator','Guest','krbtgt','DefaultAccount','WDAGUtilityAccount'
) | ForEach-Object { $_.ToLower() }

function Get-Admins {
  $m = try { (Get-LocalGroupMember Administrators -ErrorAction Stop).Name }
       catch {
         net localgroup Administrators | Select-Object -Skip 6 |
           Where-Object { $_ -and $_ -notmatch 'command completed' } | ForEach-Object { $_.Trim() }
       }
  $m | ForEach-Object { [pscustomobject]@{ Name = $_ -replace "^$([regex]::Escape($env:COMPUTERNAME))\\", '' } }
}

# AD cmdlets exist on a DC; fall back to local-only if the module is missing
$HasAD = $null -ne (Get-Command Get-ADUser -ErrorAction SilentlyContinue)

function Get-ADGroupNames($g) {
  try { Get-ADGroupMember $g -Recursive -ErrorAction Stop |
          Select-Object @{n='Group';e={$g}}, SamAccountName, objectClass }
  catch { @() }
}

$Checks = [ordered]@{
  users    = @{ Key = 'Name','SID'
                Get = { Get-LocalUser | Select-Object Name,SID,Enabled } }
  admins   = @{ Key = 'Name'
                Get = { Get-Admins } }
  tasks    = @{ Key = 'TaskPath','TaskName','Action'
                Get = { Get-ScheduledTask | Select-Object TaskPath,TaskName,State,
                        @{n='Action';e={ ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' | ' }} } }
  services = @{ Key = 'Name','PathName','StartName'
                Get = { Get-CimInstance Win32_Service | Select-Object Name,StartMode,State,PathName,StartName } }
  procs    = @{ Key = 'Name','ExecutablePath','CommandLine'
                Get = { Get-CimInstance Win32_Process | Select-Object Name,ProcessId,ParentProcessId,ExecutablePath,CommandLine } }
  autoruns = @{ Key = 'Entry Location','Entry','Image Path','Launch String'
                Get = { if (-not (Test-Path $AR)) { return @() }
                        $t = Join-Path $env:TEMP "ar_$(Get-Random).csv"
                        & $AR -accepteula -nobanner -a * -c -o $t | Out-Null
                        Import-Csv $t; Remove-Item $t -Force } }
}
if ($HasAD) {
  $Checks['domainusers'] = @{ Key = 'SamAccountName'
    Get = { Get-ADUser -Filter * -Properties Enabled,adminCount |
            Select-Object SamAccountName,Enabled,adminCount } }
  $Checks['privgroups'] = @{ Key = 'Group','SamAccountName'
    Get = { 'Domain Admins','Enterprise Admins','Administrators','Account Operators',
            'Backup Operators','Server Operators','Cert Publishers','DnsAdmins' |
            ForEach-Object { Get-ADGroupNames $_ } } }
  # Kerberoast surface: accounts with an SPN set (red adding SPNs shows up here)
  $Checks['spns'] = @{ Key = 'SamAccountName','SPN'
    Get = { Get-ADUser -Filter {ServicePrincipalName -like '*'} -Properties ServicePrincipalName |
            ForEach-Object { foreach ($s in $_.ServicePrincipalName) {
              [pscustomobject]@{ SamAccountName=$_.SamAccountName; SPN=$s } } } } }
  # AS-REP roast surface: DoesNotRequirePreAuth flag (red flipping this shows up here)
  $Checks['asrep'] = @{ Key = 'SamAccountName'
    Get = { Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} |
            Select-Object SamAccountName } }
}

# ----------------------------- Sysmon mode ------------------------------------
function Invoke-Sysmon {
  # 1. locate sysmon binary
  if (-not $SysmonBin) {
    $SysmonBin = @(
      'C:\Tools\Sysinternals Suite\Sysmon64.exe',
      'C:\Tools\Sysmon64.exe',
      "$env:SystemRoot\Sysmon64.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  }
  if (-not $SysmonBin) {
    Write-Host '[*] Sysmon not found locally, downloading from Microsoft...'
    $zip = Join-Path $env:TEMP 'Sysmon.zip'
    $ext = Join-Path $env:TEMP 'Sysmon'
    try {
      Invoke-WebRequest 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile $zip -UseBasicParsing
      Expand-Archive $zip $ext -Force
      $SysmonBin = Join-Path $ext 'Sysmon64.exe'
    } catch { Write-Error "Sysmon download failed: $_. Pre-stage it and pass -SysmonBin."; return }
  }
  Write-Host "[+] Sysmon binary: $SysmonBin"

  # 2. get a config
  if (-not $SysmonConfig) {
    $SysmonConfig = Join-Path $Dir 'sysmonconfig.xml'
    Write-Host "[*] Downloading config: $ConfigUrl"
    try { Invoke-WebRequest $ConfigUrl -OutFile $SysmonConfig -UseBasicParsing }
    catch { Write-Error "Config download failed: $_. Pre-stage it and pass -SysmonConfig."; return }
  }
  Write-Host "[+] Sysmon config: $SysmonConfig"

  # 3. install or update
  $installed = Get-Service -Name 'Sysmon64','Sysmon' -ErrorAction SilentlyContinue
  if ($installed) {
    Write-Host '[*] Sysmon already installed -> updating config (-c)'
    & $SysmonBin -accepteula -c $SysmonConfig
  } else {
    Write-Host '[*] Installing Sysmon (-i)'
    & $SysmonBin -accepteula -i $SysmonConfig
  }

  # 4. wire the Wazuh agent to read the Sysmon channel
  $ossec = 'C:\Program Files (x86)\ossec-agent\ossec.conf'
  if (-not (Test-Path $ossec)) {
    Write-Warning "ossec.conf not found at $ossec - edit the agent config manually."
  } else {
    $raw = Get-Content $ossec -Raw
    if ($raw -match 'Microsoft-Windows-Sysmon/Operational') {
      Write-Host '[=] Wazuh already reads the Sysmon channel (no change)'
    } else {
      Copy-Item $ossec "$ossec.bak_$(Get-Date -f yyyyMMddHHmmss)" -Force
      $block = @"
  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
</ossec_config>
"@
      # insert before the last closing tag
      $new = $raw -replace '(?s)</ossec_config>\s*$', $block
      Set-Content $ossec $new -Encoding UTF8
      Write-Host '[+] Added Sysmon <localfile> to ossec.conf (backup saved)'
    }
    # 5. restart the agent so it picks up the change
    $svc = Get-Service 'Wazuh','WazuhSvc','OssecSvc' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) { Restart-Service $svc.Name -Force; Write-Host "[+] Restarted $($svc.Name)" }
    else { Write-Warning 'Wazuh agent service not found - restart it manually.' }
  }
  Write-Host "`n[+] Done. Confirm Event Viewer > Applications and Services > Microsoft > Windows > Sysmon/Operational is logging,"
  Write-Host "    then confirm events arriving on the manager (172.16.10.254)."
}

# --------------------------- RollPasswords mode -------------------------------
function New-StrongPassword([int]$len = 20) {
  $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ','abcdefghijkmnpqrstuvwxyz','23456789','!@#%^&*-_=+?')
  $all  = -join $sets
  $chars = foreach ($s in $sets) { $s[(Get-Random -Maximum $s.Length)] }      # one of each class
  $chars += 1..($len - $sets.Count) | ForEach-Object { $all[(Get-Random -Maximum $all.Length)] }
  -join ($chars | Sort-Object { Get-Random })
}

function Set-Pw($sam, $pw) {
  Set-ADAccountPassword -Identity $sam -Reset -NewPassword (ConvertTo-SecureString $pw -AsPlainText -Force) -ErrorAction Stop
  Set-ADUser -Identity $sam -ChangePasswordAtLogon $false -ErrorAction SilentlyContinue
}

function Invoke-RollPasswords {
  if (-not $HasAD) { Write-Error 'AD module not available - this mode is for the DC.'; return }
  $me       = $env:USERNAME
  $scored   = $ScoredAccounts | ForEach-Object { $_.ToLower() }
  $exclude  = ($ExcludeAccounts + $me + 'krbtgt' + 'Guest') | ForEach-Object { $_.ToLower() }
  $out      = 'C:\ccdc\rolled_passwords.csv'
  $records  = [System.Collections.Generic.List[object]]::new()
  $skipped  = [System.Collections.Generic.List[string]]::new()

  Write-Host "[*] Operator account auto-excluded: $me" -ForegroundColor Yellow
  if ($scored) { Write-Host "[*] Scored accounts (will be printed): $($ScoredAccounts -join ', ')" -ForegroundColor Yellow }

  $users = Get-ADUser -Filter 'Enabled -eq $true' -Properties ServicePrincipalName
  foreach ($u in $users) {
    $sam = $u.SamAccountName; $low = $sam.ToLower()
    if ($low -like '*$')          { continue }                       # machine accounts
    if ($exclude -contains $low)  { $skipped.Add("$sam (excluded)"); continue }

    $isScored  = $scored -contains $low
    $isService = $sam -like 'svc_*' -or $u.ServicePrincipalName
    if ($isService -and -not $isScored -and -not $IncludeServiceAccounts) {
      $skipped.Add("$sam (service account - not rolled)"); continue
    }

    $pw = if ($isScored -and $NewPassword) { $NewPassword } else { New-StrongPassword }
    try {
      Set-Pw $sam $pw
      $records.Add([pscustomobject]@{ SamAccountName=$sam; NewPassword=$pw; Scored=$isScored; Service=[bool]$isService })
    } catch { Write-Warning "FAILED to roll $sam : $_" }
  }

  # write full mapping to a locked-down file (Administrators/SYSTEM only)
  $records | Export-Csv $out -NoTypeInformation
  try {
    $acl = Get-Acl $out; $acl.SetAccessRuleProtection($true,$false)
    foreach ($who in 'BUILTIN\Administrators','NT AUTHORITY\SYSTEM') {
      $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($who,'FullControl','Allow')))
    }
    Set-Acl $out $acl
  } catch { Write-Warning "Could not tighten ACL on $out : $_" }

  Write-Host "`n[+] Rolled $($records.Count) accounts. Full map (locked): $out" -ForegroundColor Green
  if ($skipped.Count) { Write-Host "[i] Skipped: $($skipped -join '; ')" }

  # print ONLY scored creds - you need these for the scoreboard right now
  $scoredRecs = $records | Where-Object Scored
  if ($scoredRecs) {
    Write-Host "`n==== SCORED ACCOUNTS - put these in the scoreboard, then confirm green ====" -ForegroundColor Cyan
    $scoredRecs | Select-Object SamAccountName,NewPassword | Format-Table -Auto | Out-String -Width 4096 | Write-Host
  } else {
    Write-Host "`n[!] No scored accounts were specified. Re-run with -ScoredAccounts so the scoreboard check accounts stay green." -ForegroundColor Red
  }
  Write-Host "[!] Service accounts were skipped. If a scored check logs in as one (e.g. LDAP as svc_ehr)," -ForegroundColor Yellow
  Write-Host "    add it to -ScoredAccounts, but know rolling it breaks whatever service runs as it until you update that service's saved credential." -ForegroundColor Yellow
  Write-Host "[!] krbtgt is NOT touched here - reset it separately with the official double-reset, never a bulk roll." -ForegroundColor Yellow
}

# ------------------------------- dispatch -------------------------------------
if ($Mode -eq 'Sysmon')        { Invoke-Sysmon; return }
if ($Mode -eq 'RollPasswords') { Invoke-RollPasswords; return }

foreach ($name in $Checks.Keys) {
  $c    = $Checks[$name]
  $file = Join-Path $Dir "$name.xml"
  $now  = @(& $c.Get)

  if ($Mode -eq 'Baseline') {
    $now | Export-Clixml $file
    Write-Host "[+] $name baseline: $($now.Count) items"
    continue
  }

  if (-not (Test-Path $file)) { Write-Warning "No baseline for $name"; continue }
  $base = @(Import-Clixml $file)

  $new = if ($base.Count -eq 0) { $now }
         elseif ($now.Count -gt 0) {
           Compare-Object $base $now -Property $c.Key -PassThru | Where-Object SideIndicator -eq '=>'
         }
  if ($new) {
    Write-Host "`n[!] NEW $name ($(@($new).Count))" -ForegroundColor Red
    $new | Select-Object * -ExcludeProperty SideIndicator | Format-List | Out-String -Width 4096 | Write-Host
  }
}

# unapproved enabled domain users (independent of baseline drift)
if ($Mode -eq 'Check' -and $HasAD) {
  $bad = Get-ADUser -Filter 'Enabled -eq $true' |
         Where-Object { $Approved -notcontains $_.SamAccountName.ToLower() -and $_.SamAccountName -notlike '*$' }
  if ($bad) {
    Write-Host "`n[!!] UNAPPROVED enabled domain users ($(@($bad).Count))" -ForegroundColor Red
    $bad | Select-Object SamAccountName,Name | Format-List | Out-String -Width 4096 | Write-Host
  }
}