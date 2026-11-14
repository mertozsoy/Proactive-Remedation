<#
.SYNOPSIS
  Remediation script for sign-in on resume from sleep.

.DESCRIPTION
  Enables CONSOLELOCK for unmanaged AC and DC settings on the active power plan.
  Preserves policy values, reapplies the same plan and verifies the resulting configuration.
  Exits 0 on success or 1 on conflict, failure or an active plan change.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedConsoleLock = 1

$PackageName = 'WakeSignIn'
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
function Invoke-PowerSetting { param([string[]]$Arguments)
    $null = & $script:PowerCfg @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Powercfg failed with exit code $LASTEXITCODE." }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($ExpectedConsoleLock -ne 1) { throw 'ExpectedConsoleLock must be 1.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
    $PowerCfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
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
    $scheme = $state[0].Scheme
    if (@($state | Where-Object { $_.Managed -and $_.Value -ne $ExpectedConsoleLock }).Count -gt 0) {
        Exit-Script 1 'PolicyConflict | Action=ReviewPowerPolicy; Changed=0'
    }
    $changed = 0
    foreach ($source in @('AC', 'DC')) {
        $current = @(Get-WakeState)
        if ($current[0].Scheme -ne $scheme) { throw 'Active power plan changed. Retry on the next schedule.' }
        if (@($current | Where-Object { $_.Managed -and $_.Value -ne $ExpectedConsoleLock }).Count -gt 0) { throw 'Power policy changed. Review the policy.' }
        $entry = $current | Where-Object { $_.Source -eq $source }
        if ($entry.Managed -or $entry.Value -eq $ExpectedConsoleLock) { continue }
        $operation = '/set' + $source.ToLowerInvariant() + 'valueindex'
        Invoke-PowerSetting -Arguments @($operation, $scheme.ToString(), 'fea3413e-7e05-4911-9a71-700331f1c294', '0e796bdb-100d-47d6-a2d5-f7d2daa51f51', '1')
        $changed++
        Write-IRTLog "Updated $source CONSOLELOCK to 1."
    }
    if ([IRT.WakePower]::ActiveScheme() -ne $scheme) { throw 'Active power plan changed. Retry on the next schedule.' }
    if ($changed -gt 0) { Invoke-PowerSetting -Arguments @('/setactive', $scheme.ToString()) }
    $verified = @(Get-WakeState)
    if ($verified[0].Scheme -ne $scheme -or [IRT.WakePower]::ActiveScheme() -ne $scheme) { throw 'Active power plan changed during verification.' }
    if (@($verified | Where-Object { $_.Value -ne $ExpectedConsoleLock }).Count -gt 0) { throw 'CONSOLELOCK verification failed.' }
    $details = ($verified | ForEach-Object { '{0}={1}; {0}Managed={2}' -f $_.Source, $_.Value, $_.Managed }) -join '; '
    if ($changed -eq 0) { Exit-Script 0 "Healthy | $details; Changed=0" }
    Exit-Script 0 "Fixed | $details; Changed=$changed"
}
catch { Exit-Script 1 "Failed | Reason=$($_.Exception.Message)" }
