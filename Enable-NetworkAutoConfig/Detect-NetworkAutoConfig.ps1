<#
.SYNOPSIS
  Detection script for disabled Wired AutoConfig and WLAN AutoConfig services.

.DESCRIPTION
  Reads the startup mode of dot3svc and WlanSvc. WlanSvc is skipped on devices without a wireless adapter. Exits 1 if a service is set to Disabled or WlanSvc is stopped, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WiredServiceName       = 'dot3svc'
$WlanServiceName        = 'WlanSvc'
$SkipWlanWithoutAdapter = $true
$CheckWlanStoppedState  = $true
$WirelessMediumIds      = @(1, 9)

$PackageName = 'NetworkAutoConfig'
$Phase       = 'Detect'
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

try {
    $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient' }

    $wirelessCount = 0
    if ($SkipWlanWithoutAdapter) { $wirelessCount = Get-WirelessAdapterCount }

    $parts = @()
    $drift = @()
    $present = 0
    $disabled = @()

    $wired = Get-AutoConfigService -Name $WiredServiceName
    if ($null -eq $wired) {
        $parts += "$WiredServiceName=Missing"
    }
    else {
        $present++
        $parts += ('{0}={1}/{2}' -f $WiredServiceName, $wired.StartMode, $wired.State)
        if ($wired.StartMode -eq 'Disabled') {
            $drift += $WiredServiceName
            $disabled += $WiredServiceName
        }
    }

    $wlan = Get-AutoConfigService -Name $WlanServiceName
    if ($null -eq $wlan) {
        $parts += "$WlanServiceName=Missing"
    }
    elseif ($SkipWlanWithoutAdapter -and $wirelessCount -eq 0) {
        $parts += "$WlanServiceName=Skipped(NoAdapter)"
    }
    else {
        $present++
        $parts += ('{0}={1}/{2}' -f $WlanServiceName, $wlan.StartMode, $wlan.State)
        if ($wlan.StartMode -eq 'Disabled') {
            $drift += $WlanServiceName
            $disabled += $WlanServiceName
        }
        elseif ($CheckWlanStoppedState -and $wlan.State -ne 'Running') {
            $drift += $WlanServiceName
        }
    }

    $parts += "WirelessAdapters=$wirelessCount"
    $summary = $parts -join '; '

    if ($present -eq 0) { Exit-Script 0 "NotApplicable | $summary" }

    if ($drift.Count -gt 0) {
        $detail = "Drift | Affected=$($drift -join ',')"
        if ($disabled.Count -gt 0) { $detail += "; Disabled=$($disabled -join ',')" }
        Exit-Script 1 "$detail; $summary"
    }

    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Detect; HResult=$($_.Exception.HResult)" }
