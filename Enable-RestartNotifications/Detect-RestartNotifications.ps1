<#
.SYNOPSIS
  Detection script for the Windows Update pending restart notification setting.

.DESCRIPTION
  Reads the RestartNotificationsAllowed2 value under the Windows Update UX settings key. Exits 1 if the value is missing or set to 0, 0 if it is enabled. Applies to Windows 11 22H2 and later only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedValue     = 1
$RegPath           = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$RegValueName      = 'RestartNotificationsAllowed2'
$MinimumBuild      = 22621
$CimTimeoutSeconds = 30

$PackageName = 'RestartNotifications'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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

try {
    $ErrorActionPreference = 'Stop'

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=UnsupportedOS' }

    $build = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
    if ($build -lt $MinimumBuild) { Exit-Script 0 "NotApplicable | Reason=UnsupportedBuild; Build=$build" }

    $current = $null
    if (Test-Path -LiteralPath $RegPath) {
        $item = Get-ItemProperty -LiteralPath $RegPath -Name $RegValueName -ErrorAction SilentlyContinue
        if ($null -ne $item) { $current = [int]($item.$RegValueName) }
    }
    Write-IRTLog ('Value={0}; Current={1}; Expected={2}' -f $RegValueName, $current, $ExpectedValue)

    if ($null -eq $current) { Exit-Script 1 "Drift | RestartNotifications=Missing; Expected=$ExpectedValue" }
    if ($current -ne $ExpectedValue) { Exit-Script 1 "Drift | RestartNotifications=$current; Expected=$ExpectedValue" }

    Exit-Script 0 "Healthy | RestartNotifications=$current"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
