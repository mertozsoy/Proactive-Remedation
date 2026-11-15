<#
.SYNOPSIS
  Rolls back a known bad camera driver using the Windows backup driver.

.DESCRIPTION
  Requires an exact model, hardware ID, bad version list and expected older
  version/provider. Uses DiRollbackDriver without UI and with a supplied reboot
  flag so no restart is initiated. Verifies version, signature and device state.
  Exits 0 only for a verified healthy result, otherwise 1. Rollback is opt-in.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetModel = ''
$TargetHardwareId = ''
$BadDriverVersions = @()
$ExpectedDriverVersion = ''
$ExpectedDriverProvider = ''
$EnableRemediation = $false
$DriverPolicyReviewApproved = $false
$VerificationAttempts = 6
$VerificationDelaySeconds = 5

$PackageName = 'CameraDriverRollback'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-CameraState {
    $classGuids = @('{ca3e7ab9-b4c3-4ae6-8251-579ef933890f}', '{6bdd1fc6-810f-11d0-bec7-08002be2092f}')
    $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter 'Present=True' -ErrorAction Stop |
        Where-Object { $classGuids -contains $_.ClassGuid -and $_.HardwareID -contains $TargetHardwareId })
    if ($devices.Count -eq 0) { return $null }
    if ($devices.Count -ne 1) { throw 'AmbiguousCamera' }
    $device = $devices[0]
    $drivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceID -eq $device.DeviceID })
    if ($drivers.Count -ne 1 -or -not $drivers[0].DriverVersion -or $null -eq $device.ConfigManagerErrorCode) {
        throw 'IncompleteCameraState'
    }
    [pscustomobject]@{
        InstanceId = $device.DeviceID
        Version = [string]$drivers[0].DriverVersion
        Provider = [string]$drivers[0].DriverProviderName
        Signed = ($drivers[0].IsSigned -eq $true)
        Problem = [int]$device.ConfigManagerErrorCode
    }
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if (-not $TargetModel -or -not $TargetHardwareId -or $BadDriverVersions.Count -eq 0 -or
        -not $ExpectedDriverVersion -or -not $ExpectedDriverProvider) {
        Exit-Script 0 'NotApplicable | Reason=ConfigurationRequired'
    }
    foreach ($badVersion in $BadDriverVersions) {
        if ([version]$ExpectedDriverVersion -ge [version]$badVersion) { throw 'InvalidVersionConfiguration' }
    }
    if ($VerificationAttempts -lt 1 -or $VerificationAttempts -gt 12 -or
        $VerificationDelaySeconds -lt 1 -or $VerificationDelaySeconds -gt 10) { throw 'InvalidVerificationConfiguration' }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($computer.Model -ne $TargetModel) { Exit-Script 0 'NotApplicable | Reason=ModelMismatch' }
    $state = Get-CameraState
    if ($null -eq $state) { Exit-Script 0 'NotApplicable | Reason=TargetCameraAbsent' }
    if ($state.Version -eq $ExpectedDriverVersion -and $state.Provider -eq $ExpectedDriverProvider -and
        $state.Signed -and $state.Problem -eq 0) {
        Exit-Script 0 "Healthy | Version=$($state.Version); Problem=0"
    }
    if ($BadDriverVersions -notcontains $state.Version -or $state.Provider -ne $ExpectedDriverProvider) {
        Exit-Script 1 "ReviewRequired | Reason=UnexpectedDriverOrDeviceState; Version=$($state.Version); Problem=$($state.Problem)"
    }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Reason=RemediationDisabled; Version=$($state.Version)" }
    if (-not $DriverPolicyReviewApproved) { Exit-Script 1 'Blocked | Reason=DriverPolicyReviewRequired' }
    if ($state.Problem -eq 14) { Exit-Script 1 'PendingReboot | Reason=DeviceRestartRequired; RestartInitiated=False' }

    if (-not ('IRT.CameraRollback' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace IRT {
    public static class CameraRollback {
        [StructLayout(LayoutKind.Sequential)]
        private struct DeviceInfo {
            public uint cbSize;
            public Guid ClassGuid;
            public uint DevInst;
            public UIntPtr Reserved;
        }
        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr classGuid, IntPtr parent);
        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiOpenDeviceInfoW(IntPtr set, string instanceId, IntPtr parent, uint flags, ref DeviceInfo data);
        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
        [DllImport("newdev.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DiRollbackDriver(IntPtr set, ref DeviceInfo data, IntPtr parent, uint flags,
            [MarshalAs(UnmanagedType.Bool)] out bool needReboot);
        public static int Rollback(string instanceId, out bool needReboot) {
            needReboot = false;
            IntPtr set = SetupDiCreateDeviceInfoList(IntPtr.Zero, IntPtr.Zero);
            if (set == new IntPtr(-1)) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
            try {
                DeviceInfo data = new DeviceInfo();
                data.cbSize = (uint)Marshal.SizeOf(typeof(DeviceInfo));
                if (!SetupDiOpenDeviceInfoW(set, instanceId, IntPtr.Zero, 0, ref data)) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                const uint ROLLBACK_FLAG_NO_UI = 0x00000001;
                if (!DiRollbackDriver(set, ref data, IntPtr.Zero, ROLLBACK_FLAG_NO_UI, out needReboot)) {
                    return Marshal.GetLastWin32Error();
                }
                return 0;
            }
            finally { SetupDiDestroyDeviceInfoList(set); }
        }
    }
}
'@ -ErrorAction Stop
    }
    $fresh = Get-CameraState
    if ($null -eq $fresh -or $fresh.InstanceId -ne $state.InstanceId -or
        $fresh.Version -ne $state.Version -or $fresh.Provider -ne $state.Provider) {
        Exit-Script 1 'Blocked | Reason=DeviceChangedBeforeRollback'
    }
    $needReboot = $false
    $nativeError = [IRT.CameraRollback]::Rollback($fresh.InstanceId, [ref]$needReboot)
    if ($nativeError -eq 259) { Exit-Script 1 'Failed | Reason=NoBackupDriver; Win32Error=259' }
    if ($nativeError -ne 0) { Exit-Script 1 "Failed | Reason=RollbackApiError; Win32Error=$nativeError" }
    if ($needReboot) { Exit-Script 1 'PendingReboot | Reason=RollbackNeedsRestart; RestartInitiated=False' }
    $verified = $null
    for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
        Start-Sleep -Seconds $VerificationDelaySeconds
        $verified = Get-CameraState
        if ($null -ne $verified -and $verified.InstanceId -eq $fresh.InstanceId -and
            $verified.Version -eq $ExpectedDriverVersion -and $verified.Provider -eq $ExpectedDriverProvider -and
            $verified.Signed -and $verified.Problem -eq 0) {
            Exit-Script 0 "Fixed | Version=$($verified.Version); Problem=0; RestartInitiated=False"
        }
    }
    if ($null -eq $verified) { Exit-Script 1 'Failed | Reason=CameraAbsentAfterRollback' }
    Exit-Script 1 "Failed | Reason=VerificationMismatch; Version=$($verified.Version); Problem=$($verified.Problem)"
}
catch { Exit-Script 1 "Failed | Reason=RemediationError; HResult=$($_.Exception.HResult)" }
