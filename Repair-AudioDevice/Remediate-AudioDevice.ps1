<#
.SYNOPSIS
  Remediation script that removes audio devices in a problem state and rescans the device tree.

.DESCRIPTION
  Removes each present audio device whose problem code is not in the ignored list, scans for hardware changes and restarts the audio services. Exits 0 when no audio device keeps an error state, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DeviceClasses        = @('MEDIA', 'AudioEndpoint')
$IgnoredProblemCodes  = @(0, 22, 24, 45)
$RemoveDevice         = $true
$ScanDeviceTree       = $true
$RestartAudioServices = $true
$MaxDevices           = 5
$RescanWaitSeconds    = 30
$MinimumBuild         = 19041
$SuccessExitCodes     = @(0, 3010)

$PackageName = 'AudioDevice'
$Phase       = 'Remediate'
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

function Invoke-PnPUtil { param([string[]]$Arguments)
    $null = & pnputil.exe @Arguments 2>&1
    [int]$LASTEXITCODE
}

function Reset-AudioDevice { param([string]$InstanceId)
    $code = Invoke-PnPUtil -Arguments @('/remove-device', $InstanceId)
    if ($SuccessExitCodes -contains $code) { return 'Removed' }
    Write-IRTLog "RemoveFailed | ExitCode=$code" 'WARN'

    $code = Invoke-PnPUtil -Arguments @('/restart-device', $InstanceId)
    if ($SuccessExitCodes -contains $code) { return 'Restarted' }
    Write-IRTLog "RestartFailed | ExitCode=$code" 'WARN'

    try {
        Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
        Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
        'Cycled'
    }
    catch {
        Write-IRTLog "CycleFailed | HResult=$($_.Exception.HResult)" 'ERROR'
        'Failed'
    }
}

function Restart-AudioStack {
    foreach ($name in @('AudioEndpointBuilder', 'Audiosrv')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $service) { continue }
        try {
            if ($service.Status -eq 'Running') { Restart-Service -Name $name -Force -ErrorAction Stop }
            else { Start-Service -Name $name -ErrorAction Stop }
            Write-IRTLog "ServiceAction | Name=$name; Action=Restarted"
        }
        catch {
            Write-IRTLog "ServiceActionFailed | Name=$name; HResult=$($_.Exception.HResult)" 'WARN'
        }
    }
}

function Wait-AudioDevice { param([int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $devices = @(Get-AudioDevice)
        if ($devices.Count -gt 0 -and @(Get-AudioErrorDevice -Devices $devices).Count -eq 0) { return $true }
        Start-Sleep -Seconds 3
    }
    $false
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient' }
    if ([int]$os.BuildNumber -lt $MinimumBuild) { Exit-Script 0 "NotApplicable | Reason=BuildTooOld; Build=$($os.BuildNumber)" }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -ne 'S-1-5-18' -or -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=RequiresSystemAnd64BitPowerShell'
    }

    $devices = @(Get-AudioDevice)
    if ($devices.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoAudioDevice' }

    $errors = @(Get-AudioErrorDevice -Devices $devices)
    if ($errors.Count -eq 0) { Exit-Script 0 "Healthy | AudioDevices=$($devices.Count); Errors=0" }

    if (-not $RemoveDevice) {
        Exit-Script 1 "Detected | AudioDevices=$($devices.Count); Errors=$($errors.Count); Action=None"
    }

    $controllerErrors = @($errors | Where-Object { $_.Class -eq 'MEDIA' })
    if ($controllerErrors.Count -gt 0) { $targets = $controllerErrors } else { $targets = $errors }
    $targets = @($targets | Sort-Object InstanceId -Unique | Select-Object -First $MaxDevices)

    $removed = 0
    $fallback = 0
    foreach ($target in $targets) {
        $method = Reset-AudioDevice -InstanceId $target.InstanceId
        if ($method -eq 'Removed') { $removed++ } else { $fallback++ }
        Write-IRTLog "DeviceReset | Class=$($target.Class); Problem=$($target.Problem); Method=$method"
    }

    if ($ScanDeviceTree) {
        $scanCode = Invoke-PnPUtil -Arguments @('/scan-devices')
        Write-IRTLog "ScanDevices | ExitCode=$scanCode"
        if (-not ($SuccessExitCodes -contains $scanCode)) {
            Write-IRTLog 'ScanDevicesFailed | Continuing to verification' 'WARN'
        }
    }

    if ($RestartAudioServices) {
        Restart-AudioStack
        Start-Sleep -Seconds 2
    }

    $healthy = Wait-AudioDevice -TimeoutSeconds $RescanWaitSeconds
    $after = @(Get-AudioDevice)
    $remaining = @(Get-AudioErrorDevice -Devices $after)

    $summary = 'AudioDevices={0}; Reset={1}; Removed={2}; Fallback={3}; Errors={4}' -f $after.Count, $targets.Count, $removed, $fallback, $remaining.Count
    if ($after.Count -eq 0) { Exit-Script 1 "Failed | $summary; Reason=NoAudioDeviceAfterRescan" }
    if ($after.Count -lt $devices.Count) { Exit-Script 1 "Failed | $summary; Reason=AudioDeviceMissing; Before=$($devices.Count)" }
    if (-not $healthy -or $remaining.Count -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
