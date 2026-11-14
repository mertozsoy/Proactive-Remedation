<#
.SYNOPSIS
  Detection script for Recycle Bin items retained longer than the approved threshold.

.DESCRIPTION
  Reads version 1 and 2 Recycle Bin metadata on fixed NTFS drive letters as SYSTEM.
  Uses the embedded UTC deletion time, never the original file modification time.
  Exits 1 for aged items or incomplete inspection, 0 for a complete healthy scan.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RetentionDays = 30
$DriveLetters = @('C:')

$PackageName = 'AgedRecycleBinItems'
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
function Assert-PlainItem { param([System.IO.FileSystemInfo]$Item)
    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Reparse point excluded.'
    }
}
function Get-RecycleRecord { param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    Assert-PlainItem $item
    if ($item.PSIsContainer -or $item.Length -lt 26 -or $item.Length -gt 65564) {
        throw 'Invalid metadata length.'
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $version = [BitConverter]::ToUInt64($bytes, 0)
    if ($version -eq 1 -and $bytes.Length -eq 544) {
        $offset = 24
        $length = 520
    }
    elseif ($version -eq 2 -and $bytes.Length -ge 30) {
        $characters = [BitConverter]::ToUInt32($bytes, 24)
        if ($characters -lt 2 -or $characters -gt 32768 -or (28L + 2L * $characters) -ne $bytes.Length) {
            throw 'Invalid metadata path length.'
        }
        $offset = 28
        $length = [int](2 * $characters)
    }
    else { throw 'Unsupported metadata format.' }
    $originalPath = [Text.Encoding]::Unicode.GetString($bytes, $offset, $length)
    if ($originalPath.IndexOf([char]0) -lt 3 -or $originalPath -notmatch '^[A-Za-z]:\\') {
        throw 'Invalid original path.'
    }
    $fileTime = [BitConverter]::ToInt64($bytes, 16)
    if ($fileTime -le 0) { throw 'Invalid deletion time.' }
    $deletedUtc = [DateTime]::FromFileTimeUtc($fileTime)
    if ($deletedUtc -lt [DateTime]'2006-01-01' -or $deletedUtc -gt [DateTime]::UtcNow) {
        throw 'Deletion time outside supported range.'
    }
    [pscustomobject]@{ DeletedUtc = $deletedUtc; Fingerprint = [Convert]::ToBase64String($bytes) }
}
function Get-RecycleInventory {
    $aged = New-Object 'System.Collections.Generic.List[object]'
    $issues = 0
    $bins = 0
    $cutoff = [DateTime]::UtcNow.AddDays(-$RetentionDays)
    foreach ($letter in $DriveLetters) {
        if ($letter -notmatch '^[A-Za-z]:$') { throw 'Invalid drive configuration.' }
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$letter'" -ErrorAction Stop
        if ($null -eq $disk -or $disk.DriveType -ne 3 -or $disk.FileSystem -ne 'NTFS') {
            throw 'Configured drive is not an available fixed NTFS volume.'
        }
        $root = Join-Path ($letter + '\') '$Recycle.Bin'
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        Assert-PlainItem (Get-Item -LiteralPath $root -Force -ErrorAction Stop)
        foreach ($bin in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop)) {
            if ($bin.Name -notmatch '^S-1-\d+(-\d+)+$') { $issues++; continue }
            try {
                Assert-PlainItem $bin
                $bins++
                $entries = @(Get-ChildItem -LiteralPath $bin.FullName -Force -ErrorAction Stop)
                foreach ($entry in $entries) {
                    if ($entry.Name -eq 'desktop.ini') { continue }
                    if ($entry.Name -cmatch '^\$R') {
                        $metadata = Join-Path $bin.FullName ('$I' + $entry.Name.Substring(2))
                        if (-not (Test-Path -LiteralPath $metadata -PathType Leaf -ErrorAction Stop)) { $issues++ }
                        continue
                    }
                    if ($entry.Name -cnotmatch '^\$I[^\\/]+$') { $issues++; continue }
                    try {
                        $record = Get-RecycleRecord $entry.FullName
                        $payload = Join-Path $bin.FullName ('$R' + $entry.Name.Substring(2))
                        if (-not (Test-Path -LiteralPath $payload -ErrorAction Stop)) { $issues++; continue }
                        Assert-PlainItem (Get-Item -LiteralPath $payload -Force -ErrorAction Stop)
                        if ($record.DeletedUtc -lt $cutoff) {
                            $aged.Add([pscustomobject]@{
                                Metadata = $entry.FullName
                                Payload = $payload
                                Bin = $bin.FullName
                                Root = $root
                                Fingerprint = $record.Fingerprint
                            })
                        }
                    }
                    catch { $issues++ }
                }
            }
            catch { $issues++ }
        }
    }
    [pscustomobject]@{ Aged = $aged.ToArray(); Issues = $issues; Bins = $bins }
}

try {
    $ErrorActionPreference = 'Stop'
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Failed | Reason=SystemContextRequired'
    }
    if ($RetentionDays -lt 1 -or $RetentionDays -gt 365 -or $DriveLetters.Count -eq 0) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }
    $inventory = Get-RecycleInventory
    if ($inventory.Issues -gt 0) {
        Exit-Script 1 "Incomplete | AgedItems=$($inventory.Aged.Count); Issues=$($inventory.Issues); RetentionDays=$RetentionDays"
    }
    if ($inventory.Aged.Count -gt 0) {
        Exit-Script 1 "Drift | AgedItems=$($inventory.Aged.Count); Issues=0; RetentionDays=$RetentionDays"
    }
    Exit-Script 0 "Healthy | AgedItems=0; Issues=0; RetentionDays=$RetentionDays"
}
catch { Exit-Script 1 "Error: InspectionFailed | HResult=$($_.Exception.HResult)" }
