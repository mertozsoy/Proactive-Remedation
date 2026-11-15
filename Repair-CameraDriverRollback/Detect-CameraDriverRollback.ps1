<#
.SYNOPSIS
  Detects an explicitly identified bad camera driver version.

.DESCRIPTION
  Checks one camera on an exact computer model and hardware ID. Exits 1 for a
  known bad driver, unexpected driver or device error, and 0 for a healthy
  approved driver or an out-of-scope device. Does not capture camera images.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetModel = ''
$TargetHardwareId = ''
$BadDriverVersions = @()
$ExpectedDriverVersion = ''
$ExpectedDriverProvider = ''

$PackageName = 'CameraDriverRollback'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-CameraState {
    $classGuids = @('{ca3e7ab9-b4c3-4ae6-8251-579ef933890f}', '{6bdd1fc6-810f-11d0-bec7-08002be2092f}')
    $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter 'Present=True' -ErrorAction Stop |
        Where-Object { $classGuids -contains $_.ClassGuid -and $_.HardwareID -contains $TargetHardwareId })
    if ($devices.Count -eq 0) { return $null }
    if ($devices.Count -ne 1) { throw 'AmbiguousCamera' }
    $device = $devices[0]
    $drivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceID -eq $device.DeviceID })
    if ($drivers.Count -ne 1 -or -not $drivers[0].DriverVersion -or $null -eq $device.ConfigManagerErrorCode) {
        throw 'IncompleteCameraState'
    }
    [pscustomobject]@{
        InstanceId = $device.DeviceID
        Version = [string]$drivers[0].DriverVersion
        Provider = [string]$drivers[0].DriverProviderName
        Signed = ($drivers[0].IsSigned -eq $true)
        Problem = [int]$device.ConfigManagerErrorCode
    }
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if (-not $TargetModel -or -not $TargetHardwareId -or $BadDriverVersions.Count -eq 0 -or
        -not $ExpectedDriverVersion -or -not $ExpectedDriverProvider) {
        Exit-Script 0 'NotApplicable | Reason=ConfigurationRequired'
    }
    foreach ($badVersion in $BadDriverVersions) {
        if ([version]$ExpectedDriverVersion -ge [version]$badVersion) { throw 'InvalidVersionConfiguration' }
    }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($computer.Model -ne $TargetModel) { Exit-Script 0 'NotApplicable | Reason=ModelMismatch' }
    $state = Get-CameraState
    if ($null -eq $state) { Exit-Script 0 'NotApplicable | Reason=TargetCameraAbsent' }
    if ($state.Version -eq $ExpectedDriverVersion -and $state.Provider -eq $ExpectedDriverProvider -and
        $state.Signed -and $state.Problem -eq 0) {
        Exit-Script 0 "Healthy | Version=$($state.Version); Problem=0"
    }
    if ($BadDriverVersions -contains $state.Version -and $state.Provider -eq $ExpectedDriverProvider) {
        Exit-Script 1 "Drift | Reason=KnownBadVersion; Version=$($state.Version); Problem=$($state.Problem)"
    }
    Exit-Script 1 "ReviewRequired | Reason=UnexpectedDriverOrDeviceState; Version=$($state.Version); Problem=$($state.Problem)"
}
catch { Exit-Script 1 "Failed | Reason=DetectionError; HResult=$($_.Exception.HResult)" }
