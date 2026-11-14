<#
.SYNOPSIS
  Detection script for the Windows power mode.

.DESCRIPTION
  Reads the user configured AC and DC power mode through the PowrProf API. Exits 1 when either one is set to Best power efficiency, 0 otherwise. Windows 10 and policy-managed energy saver are reported without changes.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ReplacementPowerMode = 'Balanced'
$MinimumBuild = 22000

$PackageName = 'PowerMode'
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

try {
    $ErrorActionPreference = 'Stop'
    $powerModes = @{
        'BestEfficiency'  = '961cc777-2547-4f9d-8174-7d86181b8a7a'
        'Balanced'        = '00000000-0000-0000-0000-000000000000'
        'BestPerformance' = 'ded574b5-45a0-4f42-8737-46345c09c238'
    }
    if (-not $powerModes.ContainsKey($ReplacementPowerMode)) {
        throw 'Invalid replacement power mode.'
    }
    if ($ReplacementPowerMode -eq 'BestEfficiency') {
        throw 'Replacement power mode cannot be BestEfficiency.'
    }
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt $MinimumBuild) {
        Exit-Script 0 "NotApplicable | Reason=Windows10OrOlder; Build=$build"
    }
    if (-not ('IRT.PowerMode' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace IRT {
    public static class PowerMode {
        [DllImport("powrprof.dll")]
        public static extern uint PowerGetUserConfiguredACPowerMode(out Guid mode);
        [DllImport("powrprof.dll")]
        public static extern uint PowerGetUserConfiguredDCPowerMode(out Guid mode);
    }
}
'@
    }
    $energySaverKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\EnergySaver'
    if (Test-Path -LiteralPath $energySaverKey) {
        $policy = Get-ItemProperty -LiteralPath $energySaverKey -Name 'EnableEnergySaver' -ErrorAction SilentlyContinue
        if ($null -ne $policy -and $null -ne $policy.EnableEnergySaver -and [int]$policy.EnableEnergySaver -eq 1) {
            Exit-Script 0 'PolicyManaged | Action=None; Reason=EnergySaverAlwaysOnPolicy'
        }
    }
    $acMode = [guid]::Empty
    $acResult = [IRT.PowerMode]::PowerGetUserConfiguredACPowerMode([ref]$acMode)
    if ($acResult -ne 0) {
        Exit-Script 1 "Error: ReadFailed | Area=AC; Code=$acResult"
    }
    $dcMode = [guid]::Empty
    $dcResult = [IRT.PowerMode]::PowerGetUserConfiguredDCPowerMode([ref]$dcMode)
    $dcSupported = $true
    if ($dcResult -ne 0) {
        $dcSupported = $false
    }
    $efficiencyMode = [guid]$powerModes['BestEfficiency']
    $acLow = $acMode -eq $efficiencyMode
    $dcLow = $dcSupported -and $dcMode -eq $efficiencyMode
    $acName = $acMode.ToString()
    foreach ($key in $powerModes.Keys) {
        if ([guid]$powerModes[$key] -eq $acMode) { $acName = $key }
    }
    $dcName = 'Unavailable'
    if ($dcSupported) {
        $dcName = $dcMode.ToString()
        foreach ($key in $powerModes.Keys) {
            if ([guid]$powerModes[$key] -eq $dcMode) { $dcName = $key }
        }
    }
    $summary = "AC=$acName; DC=$dcName; Build=$build; Target=$ReplacementPowerMode"
    if ($acLow -or $dcLow) {
        Exit-Script 1 "Drift | $summary"
    }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: CheckFailed | Type=$($_.Exception.GetType().Name); HResult=$($_.Exception.HResult)" }
