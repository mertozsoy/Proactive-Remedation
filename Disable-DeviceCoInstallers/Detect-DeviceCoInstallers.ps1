<#
.SYNOPSIS
  Detection script for the device co-installer disable setting.

.DESCRIPTION
  Checks the native registry value and type. Exits 1 when the setting is missing or differs from DWORD 1, 0 when compliant or not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedDisableCoInstallers = 1

$PackageName = 'DeviceCoInstallers'
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
function Get-CoInstallerState {
    $key = $null
    try {
        if (-not (Test-Path -LiteralPath $RegistryPath -ErrorAction Stop)) { return 'Missing' }
        $key = Get-Item -LiteralPath $RegistryPath -ErrorAction Stop
        if ($key.GetValueNames() -notcontains 'DisableCoInstallers') { return 'Missing' }
        if ($key.GetValueKind('DisableCoInstallers') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { return 'WrongType' }
        if ($key.GetValue('DisableCoInstallers') -eq $ExpectedDisableCoInstallers) { return 'Compliant' }
        return 'DifferentValue'
    }
    finally { if ($null -ne $key) { $key.Close() } }
}

try {
    $ErrorActionPreference = 'Stop'
    $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0') {
        Exit-Script 0 'NotApplicable | Reason=WindowsClient10OrLaterRequired'
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=Use64BitPowerShell'
    }
    if ($ExpectedDisableCoInstallers -ne 1) { Exit-Script 1 'Failed | Reason=ExpectedValueMustBe1' }
    $state = Get-CoInstallerState
    if ($state -eq 'Compliant') { Exit-Script 0 'Healthy | DisableCoInstallers=1; Type=DWord' }
    Exit-Script 1 "Drift | Setting=DisableCoInstallers; State=$state; Expected=1"
}
catch { Exit-Script 1 "Error: | Operation=Detect; HResult=$($_.Exception.HResult)" }
