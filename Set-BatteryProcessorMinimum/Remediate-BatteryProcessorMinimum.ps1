<#
.SYNOPSIS
  Remediation script for the minimum processor state on battery.

.DESCRIPTION
  Raises the active plan's DC processor minimum to the configured floor and verifies it. Leaves AC settings, higher minimums and policy overrides alone. Exits 0 on success or non-applicability, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumProcessorPercent = 20

$PackageName = 'BatteryProcessorMinimum'
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

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumProcessorPercent -isnot [int] -or $MinimumProcessorPercent -lt 0 -or $MinimumProcessorPercent -gt 100) {
        throw 'Invalid minimum processor percentage.'
    }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -Property PCSystemType
    $batteries = @(Get-CimInstance -ClassName Win32_Battery -Property DeviceID)
    if ($computer.PCSystemType -ne 2 -or $batteries.Count -eq 0) {
        Exit-Script 0 'NotApplicable | Reason=NotMobileWithBattery'
    }
    if (-not ('IRT.BatteryPower' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace IRT {
    public static class BatteryPower {
        [DllImport("powrprof.dll")]
        private static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("powrprof.dll")]
        private static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
        [DllImport("powrprof.dll")]
        private static extern uint PowerSettingAccessCheck(uint accessor, ref Guid setting);
        public static Guid Active() {
            IntPtr memory = IntPtr.Zero;
            uint result = PowerGetActiveScheme(IntPtr.Zero, out memory);
            if (result != 0) throw new Win32Exception((int)result);
            try { return (Guid)Marshal.PtrToStructure(memory, typeof(Guid)); }
            finally { LocalFree(memory); }
        }
        public static uint Read(Guid scheme, Guid setting) {
            Guid subgroup = new Guid("54533251-82be-4824-96c1-47b60b740d00");
            uint value;
            uint result = PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, out value);
            if (result != 0) throw new Win32Exception((int)result);
            return value;
        }
        public static bool Managed(uint accessor, Guid setting) {
            uint result = PowerSettingAccessCheck(accessor, ref setting);
            if (result == 1260) return true;
            if (result != 0) throw new Win32Exception((int)result);
            return false;
        }
    }
}
'@
    }
    $minimumSetting = [guid]'893dee8e-2bef-41e0-89c6-b55d0929964c'
    $maximumSetting = [guid]'bc5038f7-23e0-4960-96da-33abaf5935ec'
    $scheme = [IRT.BatteryPower]::Active()
    if ([IRT.BatteryPower]::Managed(1, $minimumSetting) -or [IRT.BatteryPower]::Managed(19, $scheme)) {
        Exit-Script 0 'PolicyManaged | Action=None; Reason=PowerPolicyOverride'
    }
    $current = [IRT.BatteryPower]::Read($scheme, $minimumSetting)
    $maximum = [IRT.BatteryPower]::Read($scheme, $maximumSetting)
    if ($current -gt 100 -or $maximum -gt 100) { throw 'Invalid processor state value.' }
    if ([IRT.BatteryPower]::Active() -ne $scheme) { throw 'Active scheme changed before remediation.' }
    $summary = "Scheme=$scheme; DCMinimum=$current; Floor=$MinimumProcessorPercent; DCMaximum=$maximum"
    if ($current -ge $MinimumProcessorPercent) { Exit-Script 0 "Healthy | $summary" }
    if ($maximum -lt $MinimumProcessorPercent) { Exit-Script 1 "Blocked | $summary; Reason=MaximumBelowFloor" }
    Write-IRTLog "Before | $summary"
    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    & $powercfg /setdcvalueindex $scheme.ToString() SUB_PROCESSOR PROCTHROTTLEMIN $MinimumProcessorPercent 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Powercfg failed to write the DC minimum.' }
    if ([IRT.BatteryPower]::Active() -ne $scheme) { throw 'Active scheme changed; activation skipped.' }
    if ([IRT.BatteryPower]::Managed(1, $minimumSetting) -or [IRT.BatteryPower]::Managed(19, $scheme)) {
        Exit-Script 1 'Blocked | Reason=PolicyChangedDuringRemediation; Activation=Skipped'
    }
    & $powercfg /setactive $scheme.ToString() 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Powercfg failed to apply the active plan.' }
    $verified = [IRT.BatteryPower]::Read($scheme, $minimumSetting)
    if ([IRT.BatteryPower]::Active() -ne $scheme -or $verified -ne $MinimumProcessorPercent) {
        Exit-Script 1 'Failed | Reason=VerificationMismatch'
    }
    Exit-Script 0 "Fixed | Scheme=$scheme; Previous=$current; DCMinimum=$verified; Floor=$MinimumProcessorPercent; AC=Unchanged"
}
catch { Exit-Script 1 "Error: RemediationFailed | Type=$($_.Exception.GetType().Name); HResult=$($_.Exception.HResult)" }
