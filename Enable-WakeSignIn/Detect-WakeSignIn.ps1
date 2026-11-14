<#
.SYNOPSIS
  Detection script for sign-in on resume from sleep.

.DESCRIPTION
  Checks CONSOLELOCK for AC and DC on the active power plan, including policy overrides.
  Exits 1 for drift, conflicting policy or a read failure. Exits 0 when configured correctly.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedConsoleLock = 1

$PackageName = 'WakeSignIn'
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
function Get-WakeState {
    $scheme = [IRT.WakePower]::ActiveScheme()
    $policyKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51')
    try {
        foreach ($source in @('AC', 'DC')) {
            $valueName = $source + 'SettingIndex'
            $managed = $null -ne $policyKey -and $policyKey.GetValueNames() -contains $valueName
            if ($managed) {
                if ($policyKey.GetValueKind($valueName) -ne [Microsoft.Win32.RegistryValueKind]::DWord) { throw 'Invalid policy value type.' }
                $value = [int]$policyKey.GetValue($valueName)
            }
            else { $value = [IRT.WakePower]::ReadValue($scheme, ($source -eq 'AC')) }
            if ($value -notin @(0, 1)) { throw 'Invalid CONSOLELOCK value.' }
            [pscustomobject]@{ Source = $source; Value = $value; Managed = $managed; Scheme = $scheme }
        }
    }
    finally { if ($null -ne $policyKey) { $policyKey.Dispose() } }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($ExpectedConsoleLock -ne 1) { throw 'ExpectedConsoleLock must be 1.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
    if (-not ('IRT.WakePower' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace IRT {
    public static class WakePower {
        [DllImport("powrprof.dll")] private static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
        [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("powrprof.dll")] private static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
        [DllImport("powrprof.dll")] private static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
        public static Guid ActiveScheme() {
            IntPtr pointer = IntPtr.Zero;
            uint result = PowerGetActiveScheme(IntPtr.Zero, out pointer);
            try {
                if (result != 0) throw new Win32Exception((int)result);
                if (pointer == IntPtr.Zero) throw new InvalidOperationException("No active power plan.");
                return (Guid)Marshal.PtrToStructure(pointer, typeof(Guid));
            } finally { if (pointer != IntPtr.Zero) LocalFree(pointer); }
        }
        public static uint ReadValue(Guid scheme, bool ac) {
            Guid subgroup = new Guid("fea3413e-7e05-4911-9a71-700331f1c294");
            Guid setting = new Guid("0e796bdb-100d-47d6-a2d5-f7d2daa51f51");
            uint value;
            uint result = ac ? PowerReadACValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, out value)
                             : PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, out value);
            if (result != 0) throw new Win32Exception((int)result);
            return value;
        }
    }
}
'@ -ErrorAction Stop
    }
    $state = @(Get-WakeState)
    if ([IRT.WakePower]::ActiveScheme() -ne $state[0].Scheme) { throw 'Active power plan changed. Retry on the next schedule.' }
    $details = ($state | ForEach-Object { '{0}={1}; {0}Managed={2}' -f $_.Source, $_.Value, $_.Managed }) -join '; '
    if (@($state | Where-Object { $_.Managed -and $_.Value -ne $ExpectedConsoleLock }).Count -gt 0) {
        Exit-Script 1 "PolicyConflict | $details; Action=ReviewPowerPolicy"
    }
    if (@($state | Where-Object { $_.Value -ne $ExpectedConsoleLock }).Count -gt 0) { Exit-Script 1 "Drift | $details" }
    Exit-Script 0 "Healthy | $details"
}
catch { Exit-Script 1 "Failed | Reason=$($_.Exception.Message)" }
