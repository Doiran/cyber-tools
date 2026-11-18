#Requires -RunAsAdministrator
<#
  Turn AS-REP roasting off on the domain.
  AS-REP roasting only works against accounts with the DONT_REQ_PREAUTH flag
  (ADUC: "Do not require Kerberos preauthentication"). This clears that flag on
  every account that has it, so there is nothing left to AS-REP roast.

  Safe to re-run: if red re-sets the flag on an account, run again to clear it.
    -Report            Only list vulnerable accounts; change nothing.
    -ExcludeAccounts   SamAccountNames to leave alone (rare; a legacy app may need preauth off).
  Supports -WhatIf / -Confirm.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
  [switch]$Report,
  [string[]]$ExcludeAccounts = @()
)

if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
  Write-Error 'ActiveDirectory module not found - run this on the DC.'; return
}

$exclude = $ExcludeAccounts | ForEach-Object { $_.ToLower() }

# Every account with DONT_REQ_PREAUTH set = the entire AS-REP roastable surface
$vuln = Get-ADUser -Filter { DoesNotRequirePreAuth -eq $true } -Properties DoesNotRequirePreAuth, Enabled |
        Where-Object { $exclude -notcontains $_.SamAccountName.ToLower() }

if (-not $vuln) {
  Write-Host '[+] No accounts have DONT_REQ_PREAUTH set - AS-REP roasting already off.' -ForegroundColor Green
  return
}

Write-Host "[!] AS-REP roastable accounts (DONT_REQ_PREAUTH set): $(@($vuln).Count)" -ForegroundColor Yellow
$vuln | Select-Object SamAccountName, Enabled | Format-Table -Auto | Out-String -Width 4096 | Write-Host

if ($Report) { Write-Host '[i] -Report set: no changes made.'; return }

$fixed = 0
foreach ($u in $vuln) {
  $sam = $u.SamAccountName
  if ($PSCmdlet.ShouldProcess($sam, 'Clear DONT_REQ_PREAUTH (require Kerberos preauth)')) {
    try {
      Set-ADAccountControl -Identity $sam -DoesNotRequirePreAuth $false -ErrorAction Stop
      Write-Host "  [+] Preauth now required: $sam"
      $fixed++
    } catch { Write-Warning "  FAILED on $sam : $_" }
  }
}

# verify nothing remains
$left = @(Get-ADUser -Filter { DoesNotRequirePreAuth -eq $true } |
          Where-Object { $exclude -notcontains $_.SamAccountName.ToLower() }).Count
Write-Host "`n[+] Cleared $fixed account(s). Still flagged (should be 0, excludes aside): $left" -ForegroundColor Green