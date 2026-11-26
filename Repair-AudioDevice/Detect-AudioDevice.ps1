<#
.SYNOPSIS
  Detection script for audio devices that sit in a Windows problem state.

.DESCRIPTION
  Reads present PnP devices in the MEDIA and AudioEndpoint classes and reports every device whose problem code is not in the ignored list. Exits 1 if such a device is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DeviceClasses       = @('MEDIA', 'AudioEndpoint')
$IgnoredProblemCodes = @(0, 22, 24, 45)

$PackageName = 'AudioDevice'
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

function Get-DeviceProblem { param($Device)
    $value = $null
    if ($Device.PSObject.Properties['Problem']) { $value = $Device.Problem }
    elseif ($Device.PSObject.Properties['ConfigManagerErrorCode']) { $value = $Device.ConfigManagerErrorCode }
    if ($null -eq $value) { return 0 }
    return [int]$value
}

function Get-AudioDevice {
    $found = @()
    $devices = @(Get-PnpDevice -PresentOnly -Class $DeviceClasses -ErrorAction SilentlyContinue)
    foreach ($device in $devices) {
        $problem = Get-DeviceProblem -Device $device
        $found += [pscustomobject]@{
            InstanceId   = [string]$device.InstanceId
            Class        = [string]$device.Class
            FriendlyName = [string]$device.FriendlyName
            Status       = [string]$device.Status
            Problem      = $problem
        }
    }
    $found
}

function Get-AudioErrorDevice { param($Devices)
    @($Devices | Where-Object { $IgnoredProblemCodes -notcontains $_.Problem })
}

try {
    $devices = @(Get-AudioDevice)
    if ($devices.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoAudioDevice' }

    $errors = @(Get-AudioErrorDevice -Devices $devices)
    if ($errors.Count -eq 0) { Exit-Script 0 "Healthy | AudioDevices=$($devices.Count); Errors=0" }

    $classes = (@($errors | Sort-Object Class -Unique | ForEach-Object { '{0}({1})' -f $_.Class, $_.Problem }) -join ',')
    Exit-Script 1 "Drift | AudioDevices=$($devices.Count); Errors=$($errors.Count); Classes=$classes"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
