<#
.SYNOPSIS
  Remediation script for the Windows Update pending restart notification setting.

.DESCRIPTION
  Enables the RestartNotificationsAllowed2 value under the Windows Update UX settings key so users get a toast when an update is waiting on a restart. Verifies the value after writing and exits 0 only when it reads back as 1.

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
$Phase       = 'Remediate'
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
function Get-SettingValue {
    $value = $null
    if (Test-Path -LiteralPath $RegPath) {
        $item = Get-ItemProperty -LiteralPath $RegPath -Name $RegValueName -ErrorAction SilentlyContinue
        if ($null -ne $item) { $value = [int]($item.$RegValueName) }
    }
    $value
}

try {
    $ErrorActionPreference = 'Stop'

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=UnsupportedOS' }

    $build = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
    if ($build -lt $MinimumBuild) { Exit-Script 0 "NotApplicable | Reason=UnsupportedBuild; Build=$build" }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try { $isSystem = $identity.User.Value -eq 'S-1-5-18' } finally { $identity.Dispose() }
    if (-not $isSystem) { Exit-Script 1 'Failed | Reason=SystemContextRequired' }

    $previous = Get-SettingValue
    Write-IRTLog ('Value={0}; Previous={1}; Expected={2}' -f $RegValueName, $previous, $ExpectedValue)

    if ($previous -eq $ExpectedValue) { Exit-Script 0 "Healthy | RestartNotifications=$ExpectedValue" }

    if (-not (Test-Path -LiteralPath $RegPath)) {
        New-Item -Path $RegPath -Force -ErrorAction Stop | Out-Null
        Write-IRTLog "Action=CreatedKey"
    }

    New-ItemProperty -LiteralPath $RegPath -Name $RegValueName -Value $ExpectedValue -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-IRTLog "Action=SetValue; Value=$ExpectedValue"

    $verified = Get-SettingValue
    if ($verified -ne $ExpectedValue) {
        Exit-Script 1 "Failed | RestartNotifications=$verified; Expected=$ExpectedValue"
    }

    Exit-Script 0 "Fixed | Previous=$previous; RestartNotifications=$verified"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
