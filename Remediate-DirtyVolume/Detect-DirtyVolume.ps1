<#
.SYNOPSIS
  Detection script for fixed NTFS volumes that carry the dirty bit.

.DESCRIPTION
  Reads the dirty flag of every fixed NTFS volume through the volume control
  code. Exits 1 if at least one volume is dirty, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExcludedDriveLetters = @()

$PackageName = 'DirtyVolume'
$Phase       = 'Detect'
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

try {
    $volumes = @(Get-TargetVolume)
    if ($volumes.Count -eq 0) { Exit-Script 0 'NotApplicable | No fixed NTFS volume' }

    $dirty = @()
    $unreadable = @()
    $checked = 0
    foreach ($volume in $volumes) {
        $flags = [DirtyVolumeNative]::GetFlags($volume)
        if ($flags -lt 0) { $unreadable += $volume; Write-IRTLog "Dirty flag unreadable: $volume"; continue }
        $checked++
        if ($flags -eq 1) { $dirty += $volume }
    }

    $detail = "Checked=$checked; Unreadable=$($unreadable.Count)"
    if ($dirty.Count -gt 0) { Exit-Script 1 "Dirty | Volumes=$($dirty -join ','); Count=$($dirty.Count); $detail" }
    Exit-Script 0 "Healthy | DirtyVolumes=0; $detail"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
