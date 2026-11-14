<#
.SYNOPSIS
  Remediation script for the Windows power mode.

.DESCRIPTION
  Reads the user configured AC and DC power mode. When either one is set to Best power efficiency it writes the configured replacement mode and verifies the new value. Exits 0 on success or non-applicability, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ReplacementPowerMode = 'Balanced'
$MinimumBuild = 22000

$PackageName = 'PowerMode'
$Phase = 'Remediate'
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
function Get-PowerModeName { param([guid]$Mode, [hashtable]$Modes)
    foreach ($key in $Modes.Keys) {
        if ([guid]$Modes[$key] -eq $Mode) { return $key }
    }
    return $Mode.ToString()
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
        [DllImport("powrprof.dll")]
        public static extern uint PowerSetUserConfiguredACPowerMode(ref Guid mode);
        [DllImport("powrprof.dll")]
        public static extern uint PowerSetUserConfiguredDCPowerMode(ref Guid mode);
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
    $targetMode = [guid]$powerModes[$ReplacementPowerMode]
    $acLow = $acMode -eq $efficiencyMode
    $dcLow = $dcSupported -and $dcMode -eq $efficiencyMode
    $acName = Get-PowerModeName -Mode $acMode -Modes $powerModes
    $dcName = 'Unavailable'
    if ($dcSupported) {
        $dcName = Get-PowerModeName -Mode $dcMode -Modes $powerModes
    }
    $previous = "AC=$acName; DC=$dcName"
    if (-not $acLow -and -not $dcLow) {
        Exit-Script 0 "Healthy | AC=$acName; DC=$dcName; Build=$build"
    }
    Write-IRTLog "Before | $previous; SupportedDC=$dcSupported"
    if ($acLow) {
        $setAc = $targetMode
        $setResult = [IRT.PowerMode]::PowerSetUserConfiguredACPowerMode([ref]$setAc)
        if ($setResult -ne 0) {
            Exit-Script 1 "Failed | Area=AC; Code=$setResult; Previous=$acName"
        }
    }
    if ($dcLow) {
        $setDc = $targetMode
        $setResult = [IRT.PowerMode]::PowerSetUserConfiguredDCPowerMode([ref]$setDc)
        if ($setResult -ne 0) {
            Exit-Script 1 "Failed | Area=DC; Code=$setResult; Previous=$dcName"
        }
    }
    Start-Sleep -Seconds 1
    $verifyAc = [guid]::Empty
    $verifyResult = [IRT.PowerMode]::PowerGetUserConfiguredACPowerMode([ref]$verifyAc)
    if ($verifyResult -ne 0) {
        Exit-Script 1 "Failed | Reason=VerificationReadFailed; Area=AC; Code=$verifyResult"
    }
    if ($verifyAc -eq $efficiencyMode) {
        Exit-Script 1 'Failed | Reason=VerificationMismatch; Area=AC'
    }
    $finalAc = Get-PowerModeName -Mode $verifyAc -Modes $powerModes
    $finalDc = 'Unavailable'
    if ($dcSupported) {
        $verifyDc = [guid]::Empty
        $verifyResult = [IRT.PowerMode]::PowerGetUserConfiguredDCPowerMode([ref]$verifyDc)
        if ($verifyResult -ne 0) {
            Exit-Script 1 "Failed | Reason=VerificationReadFailed; Area=DC; Code=$verifyResult"
        }
        if ($verifyDc -eq $efficiencyMode) {
            Exit-Script 1 'Failed | Reason=VerificationMismatch; Area=DC'
        }
        $finalDc = Get-PowerModeName -Mode $verifyDc -Modes $powerModes
    }
    Exit-Script 0 "Fixed | Previous=$previous; AC=$finalAc; DC=$finalDc; Target=$ReplacementPowerMode"
}
catch { Exit-Script 1 "Error: RemediationFailed | Type=$($_.Exception.GetType().Name); HResult=$($_.Exception.HResult)" }
