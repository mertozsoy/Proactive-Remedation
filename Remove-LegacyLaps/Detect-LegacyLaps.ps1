<#
.SYNOPSIS
  Detection script for legacy Microsoft LAPS remnants.

.DESCRIPTION
  Checks MSI registrations, the AdmPwd CSE registration and legacy policy. Exits 1 if remnants exist, 0 otherwise. Does not read passwords.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'LegacyLaps'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-LegacyLapsProduct {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ($item.DisplayName -eq 'Local Administrator Password Solution' -and $item.Publisher -eq 'Microsoft Corporation') {
                [pscustomobject]@{ Code = $key.PSChildName; Msi = ([int]$item.WindowsInstaller -eq 1) }
            }
        }
    }
}
try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $products = @(Get-LegacyLapsProduct)
    $cse = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\GPExtensions\{D76B9641-3288-4f75-942D-087DE603E3EA}' -ErrorAction Stop
    $policy = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft Services\AdmPwd' -ErrorAction Stop
    $summary = "Products=$($products.Count); CseRegistered=$cse; LegacyPolicy=$policy"
    if ($products.Count -gt 0 -or $cse -or $policy) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error | Reason=InventoryFailed; HResult={0}' -f $_.Exception.HResult) }
