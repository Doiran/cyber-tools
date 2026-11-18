$gooseName   = "GooseDesktop"                     
$gooseExe    = Join-Path $PSScriptRoot "GooseDesktop.exe"     
$destructive     = $true                          
$checkEvery  = 3                                  
$gooseAmount = 5

Add-Type -AssemblyName System.Windows.Forms

while ($gooseAmount) {
    Start-Process $gooseExe
    $gooseAmount--
}

$prevCount = (Get-Process -Name $gooseName -ErrorAction SilentlyContinue).Count

while ($true) {
    $now = (Get-Process -Name $gooseName -ErrorAction SilentlyContinue).Count

    if ($now -lt $prevCount) {
        [System.Windows.Forms.MessageBox]::Show(
            "Mess with the honk, you get the bonk.",
            "HONK",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null

        if ($destruction) {
            Restart-Computer -Force
        }
    }

    $prevCount = (Get-Process -Name $gooseName -ErrorAction SilentlyContinue).Count
    Start-Sleep -Seconds $checkEvery
}
