<#
.SYNOPSIS
  Detection script for Windows activation.

.DESCRIPTION
  Checks the license status of the installed Windows edition. Exits 1 if Windows is not activated.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PackageName = 'WindowsActivation'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$WindowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
$StatusText   = @{ 0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'OOBGrace'; 3 = 'OOTGrace'; 4 = 'NonGenuineGrace'; 5 = 'Notification'; 6 = 'ExtendedGrace' }

try {
    $lp = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='$WindowsAppId' AND PartialProductKey IS NOT NULL" -ErrorAction Stop |
          Sort-Object LicenseStatus | Select-Object -First 1
    if (-not $lp) { Exit-Script 1 'NoProductKeyInstalled' }
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    $summary = 'Status={0}; Edition={1}; Channel={2}; KeyEnd={3}' -f $StatusText[[int]$lp.LicenseStatus], $edition, $lp.ProductKeyChannel, $lp.PartialProductKey
    if ($lp.LicenseStatus -eq 1) { Exit-Script 0 "Activated | $summary" }
    Exit-Script 1 "NotActivated | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
