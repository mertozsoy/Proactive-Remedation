<#
.SYNOPSIS
  Remediation script for a stopped or disabled Microsoft Office Click-to-Run service.

.DESCRIPTION
  Restores the automatic startup type when the ClickToRunSvc service is disabled or set to
  Manual, starts the service and waits for the running state. Exits 0 when the service runs,
  1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName = 'ClickToRunSvc'
$DefaultStartMode = 'Automatic'
$RestoreStartupType = $true
$UpgradeManualStartMode = $false
$StartTimeoutSeconds = 60

$PackageName = 'ClickToRunService'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Wait-ServiceRunning {
    param([int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $state = (Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue).State
        if ($state -eq 'Running') { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

try {
    $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient' }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -ne 'S-1-5-18' -or -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=RequiresSystemAnd64BitPowerShell'
    }

    $service = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 1 'Failed | Reason=ServiceMissing; Action=RepairOrReinstallOffice' }

    $initialState = $service.State
    $modeFixed = $false
    $modeAllowed = ($service.StartMode -eq 'Disabled') -or ($service.StartMode -eq 'Manual' -and $UpgradeManualStartMode)
    if ($modeAllowed -and $RestoreStartupType) {
        try {
            Set-Service -Name $ServiceName -StartupType $DefaultStartMode -ErrorAction Stop
            $verifiedMode = (Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$ServiceName'" -ErrorAction Stop).StartMode
            if ($verifiedMode -eq 'Auto') { $modeFixed = $true }
            Write-IRTLog "StartMode | New=$verifiedMode"
        }
        catch {
            Write-IRTLog "StartModeFailed | HResult=$($_.Exception.HResult)" 'ERROR'
        }
    }

    $serviceStarted = $false
    $service = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($service.State -ne 'Running') {
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            $serviceStarted = $true
            Write-IRTLog 'ServiceStartRequested'
        }
        catch {
            Write-IRTLog "ServiceStartFailed | HResult=$($_.Exception.HResult)" 'ERROR'
        }
        $null = Wait-ServiceRunning -TimeoutSeconds $StartTimeoutSeconds
    }

    $service = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$ServiceName'" -ErrorAction Stop
    $summary = 'Service={0}; State={1}; StartMode={2}; InitialState={3}; ModeFixed={4}; ServiceStarted={5}' -f $service.Name, $service.State, $service.StartMode, $initialState, $modeFixed, $serviceStarted

    if ($service.State -ne 'Running') {
        Write-IRTLog "ServiceExitCode | Value=$($service.ExitCode)" 'WARN'
        Exit-Script 1 "Failed | $summary; ExitCode=$($service.ExitCode)"
    }
    if ($service.StartMode -eq 'Disabled') { Exit-Script 1 "Failed | $summary" }
    if ($modeFixed -or $serviceStarted) { Exit-Script 0 "Fixed | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
