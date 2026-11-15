<#
.SYNOPSIS
  Remediation script that schedules a boot time chkdsk for dirty volumes.

.DESCRIPTION
  Reads the dirty flag of every fixed NTFS volume. For each dirty volume the
  script clears autochk exclusions with chkntfs /d and schedules a check at the
  next start with chkntfs /c. Verification reads the BootExecute exclusions
  again and re-reads the dirty flag. The device is never restarted. Exits 0
  when the check is scheduled and 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExcludedDriveLetters = @()
$ResetBootExclusions  = $true
$ScheduleBootCheck    = $true

$PackageName = 'DirtyVolume'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

$DirtyVolumeSource = @'
using System;
using System.Runtime.InteropServices;

public static class DirtyVolumeNative
{
    private const uint GenericRead = 0x80000000;
    private const uint ReadAttributes = 0x00000080;
    private const uint Synchronize = 0x00100000;
    private const uint Traverse = 0x00000020;
    private const uint ShareReadWrite = 0x00000003;
    private const uint OpenExisting = 3;
    private const uint FsctlIsVolumeDirty = 0x00090078;
    private const uint VolumeIsDirty = 0x00000001;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(IntPtr handle, uint code, IntPtr inBuffer, uint inSize, out uint outBuffer, uint outSize, out uint returned, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    public static int GetFlags(string volume)
    {
        string path = @"\\.\" + volume;
        IntPtr handle = CreateFileW(path, GenericRead, ShareReadWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (IsInvalid(handle))
        {
            handle = CreateFileW(path, ReadAttributes | Synchronize | Traverse, ShareReadWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        }
        if (IsInvalid(handle))
        {
            return -1;
        }
        try
        {
            uint flags;
            uint returned;
            if (!DeviceIoControl(handle, FsctlIsVolumeDirty, IntPtr.Zero, 0, out flags, 4, out returned, IntPtr.Zero))
            {
                return -1;
            }
            return (int)(flags & VolumeIsDirty);
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    private static bool IsInvalid(IntPtr handle)
    {
        return handle == IntPtr.Zero || handle == new IntPtr(-1);
    }
}
'@
if (-not ('DirtyVolumeNative' -as [type])) { Add-Type -TypeDefinition $DirtyVolumeSource -ErrorAction Stop }

function Get-TargetVolume {
    $excluded = @()
    foreach ($letter in $ExcludedDriveLetters) { $excluded += ([string]$letter).TrimEnd(':').ToUpper() }
    $targets = @()
    foreach ($disk in (Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
        if ($disk.FileSystem -ne 'NTFS') { continue }
        if ($disk.DeviceID -notmatch '^[A-Za-z]:$') { continue }
        if ($excluded -contains $disk.DeviceID.Substring(0, 1).ToUpper()) { continue }
        $targets += $disk.DeviceID.ToUpper()
    }
    $targets
}

function Get-AutochkExclusion {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager')
    if ($null -eq $key) { return @() }
    try {
        $value = $key.GetValue('BootExecute', $null)
        if ($null -eq $value) { return @() }
        $letters = @()
        foreach ($entry in @($value)) {
            foreach ($match in [regex]::Matches([string]$entry, '/k:([A-Za-z](?:,[A-Za-z])*)')) {
                foreach ($letter in $match.Groups[1].Value.Split(',')) {
                    $drive = $letter.ToUpper()
                    if ($letters -notcontains $drive) { $letters += $drive }
                }
            }
        }
        return $letters
    }
    finally { $key.Dispose() }
}

function Invoke-Chkntfs { param([string[]]$ArgumentList)
    $tool = Join-Path $env:SystemRoot 'System32\chkntfs.exe'
    if (-not (Test-Path -LiteralPath $tool)) { throw 'chkntfs.exe is not available.' }
    $output = & $tool @ArgumentList 2>&1
    $code = $LASTEXITCODE
    Write-IRTLog "chkntfs $($ArgumentList -join ' ') | ExitCode=$code | Output=$(@($output) -join ' ')"
    return [pscustomobject]@{ ExitCode = $code }
}

try {
    $volumes = @(Get-TargetVolume)
    if ($volumes.Count -eq 0) { Exit-Script 0 'NotApplicable | No fixed NTFS volume' }

    $dirty = @()
    foreach ($volume in $volumes) {
        if ([DirtyVolumeNative]::GetFlags($volume) -eq 1) { $dirty += $volume }
    }
    if ($dirty.Count -eq 0) { Exit-Script 0 "Healthy | DirtyVolumes=0; Checked=$($volumes.Count); Action=None" }

    $excludedBefore = @(Get-AutochkExclusion)
    $beforeText = 'none'
    if ($excludedBefore.Count -gt 0) { $beforeText = $excludedBefore -join ',' }
    Write-IRTLog "Dirty volumes | Volumes=$($dirty -join ','); AutochkExclusions=$beforeText"

    if (-not $ScheduleBootCheck) {
        Exit-Script 1 "Detected | Volumes=$($dirty -join ','); Action=None; Reason=ScheduleBootCheckDisabled; AutochkExclusions=$beforeText"
    }

    if (-not $ResetBootExclusions) {
        foreach ($volume in $dirty) {
            if ($excludedBefore -contains $volume.Substring(0, 1)) {
                Exit-Script 1 "Failed | Volumes=$($dirty -join ','); Volume=$volume; Reason=ExcludedFromAutochk; ResetBootExclusions=False"
            }
        }
    }

    if ($ResetBootExclusions -and $excludedBefore.Count -gt 0) {
        $reset = Invoke-Chkntfs -ArgumentList @('/d')
        if ($reset.ExitCode -ne 0) {
            Exit-Script 1 "Failed | Volumes=$($dirty -join ','); Step=ResetExclusions; ExitCode=$($reset.ExitCode)"
        }
    }

    $scheduled = @()
    foreach ($volume in $dirty) {
        $result = Invoke-Chkntfs -ArgumentList @('/c', $volume)
        if ($result.ExitCode -ne 0) {
            Exit-Script 1 "Failed | Volumes=$($dirty -join ','); Volume=$volume; Step=ScheduleCheck; ExitCode=$($result.ExitCode)"
        }
        $scheduled += $volume
    }

    $excludedAfter = @(Get-AutochkExclusion)
    foreach ($volume in $scheduled) {
        if ($excludedAfter -contains $volume.Substring(0, 1)) {
            Exit-Script 1 "Failed | Volumes=$($dirty -join ','); Volume=$volume; Reason=StillExcluded; AutochkExclusions=$($excludedAfter -join ',')"
        }
    }

    $pending = 0
    foreach ($volume in $scheduled) {
        if ([DirtyVolumeNative]::GetFlags($volume) -eq 1) { $pending++ }
    }

    $afterText = 'none'
    if ($excludedAfter.Count -gt 0) { $afterText = $excludedAfter -join ',' }

    Exit-Script 0 "Fixed | Volumes=$($scheduled -join ','); Scheduled=$($scheduled.Count); DirtyPending=$pending; AutochkExclusions=$beforeText->$afterText; CheckType=BootTime; RestartRequired=True"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
