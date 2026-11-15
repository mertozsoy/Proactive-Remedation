<#
.SYNOPSIS
  Remediation script for disabled Wired AutoConfig and WLAN AutoConfig services.

.DESCRIPTION
  Restores the default startup type of dot3svc and WlanSvc when it is Disabled, starts both services and waits for the running state. Exits 0 when the services are running, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WiredServiceName       = 'dot3svc'
$WlanServiceName        = 'WlanSvc'
$WiredStartupType       = 'Manual'
$WlanStartupType        = 'Automatic'
$SkipWlanWithoutAdapter = $true
$WirelessMediumIds      = @(1, 9)
$RestoreStartupType     = $true
$StartServices          = $true
$StartTimeoutSeconds    = 30

$PackageName = 'NetworkAutoConfig'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

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

function Get-AutoConfigService {
    param([string]$Name)
    Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$Name'" -ErrorAction SilentlyContinue
}

function Get-WirelessAdapterCount {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $WirelessMediumIds -contains [int]$_.NdisPhysicalMedium
    })
    return $adapters.Count
}

function Wait-ServiceRunning {
    param([string]$Name, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $state = (Get-AutoConfigService -Name $Name).State
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

    $wirelessCount = 0
    if ($SkipWlanWithoutAdapter) { $wirelessCount = Get-WirelessAdapterCount }

    $plan = @(
        [pscustomobject]@{ Name = $WiredServiceName; StartupType = $WiredStartupType },
        [pscustomobject]@{ Name = $WlanServiceName; StartupType = $WlanStartupType }
    )
    $before = @{}
    $startRequested = 0

    foreach ($item in $plan) {
        if ($item.Name -eq $WlanServiceName -and $SkipWlanWithoutAdapter -and $wirelessCount -eq 0) { continue }

        $service = Get-AutoConfigService -Name $item.Name
        if ($null -eq $service) { continue }

        $before[$item.Name] = [string]$service.StartMode

        if ($service.StartMode -eq 'Disabled' -and $RestoreStartupType) {
            try {
                Set-Service -Name $item.Name -StartupType $item.StartupType -ErrorAction Stop
                Write-IRTLog "StartModeSet | Service=$($item.Name); Value=$($item.StartupType)"
            }
            catch {
                Write-IRTLog "StartModeFailed | Service=$($item.Name); HResult=$($_.Exception.HResult)" 'ERROR'
            }
        }

        $requireRunning = ($before[$item.Name] -eq 'Disabled' -or $item.Name -eq $WlanServiceName)
        $service = Get-AutoConfigService -Name $item.Name
        if ($StartServices -and $requireRunning -and $service.State -ne 'Running') {
            try {
                Start-Service -Name $item.Name -ErrorAction Stop
                $startRequested++
                Write-IRTLog "ServiceStartRequested | Service=$($item.Name)"
                $null = Wait-ServiceRunning -Name $item.Name -TimeoutSeconds $StartTimeoutSeconds
            }
            catch {
                Write-IRTLog "ServiceStartFailed | Service=$($item.Name); HResult=$($_.Exception.HResult)" 'ERROR'
            }
        }
    }

    $detail = @()
    $present = 0
    $modeFixed = 0
    $failed = $false

    foreach ($item in $plan) {
        if ($item.Name -eq $WlanServiceName -and $SkipWlanWithoutAdapter -and $wirelessCount -eq 0) {
            $detail += "$($item.Name)=Skipped(NoAdapter)"
            continue
        }

        $service = Get-AutoConfigService -Name $item.Name
        if ($null -eq $service) {
            $detail += "$($item.Name)=Missing"
            continue
        }

        $present++
        $from = $before[$item.Name]
        if ($null -eq $from) { $from = [string]$service.StartMode }

        if ($from -ne $service.StartMode) {
            $detail += ('{0}={1}->{2}/{3}' -f $item.Name, $from, $service.StartMode, $service.State)
        }
        else {
            $detail += ('{0}={1}/{2}' -f $item.Name, $service.StartMode, $service.State)
        }

        if ($from -eq 'Disabled' -and $service.StartMode -ne 'Disabled') { $modeFixed++ }
        if ($service.StartMode -eq 'Disabled') { $failed = $true }

        $requireRunning = ($from -eq 'Disabled' -or $item.Name -eq $WlanServiceName)
        if ($StartServices -and $requireRunning -and $service.State -ne 'Running') { $failed = $true }
    }

    $summary = $detail -join '; '
    if ($present -eq 0) { Exit-Script 0 "NotApplicable | $summary" }

    $summary = '{0}; StartModeFixed={1}; Started={2}' -f $summary, $modeFixed, $startRequested
    if ($failed) { Exit-Script 1 "Failed | $summary" }
    if ($modeFixed -gt 0 -or $startRequested -gt 0) { Exit-Script 0 "Fixed | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
