<#
.SYNOPSIS
  Detection script for old Intune Win32 application cache content.

.DESCRIPTION
  Checks GUID_version directories in Windows IMECache. Every entry must be older
  than the retention period. Exits 1 when eligible bytes meet the cleanup threshold,
  0 otherwise. Recent content and reparse points are excluded.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 30
$MinimumReclaimMB = 512
$MaximumEntriesPerDirectory = 50000

$PackageName = 'OldIMECache'
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

function Assert-CachePath { param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath -ne $CacheRoot -and -not $fullPath.StartsWith($CacheRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutsideCacheRoot'
    }
    $current = $fullPath
    while ($current) {
        $entry = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ReparsePoint' }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-StaleCacheTree { param([string]$Path)
    Assert-CachePath -Path $Path
    $entries = New-Object 'System.Collections.Generic.List[System.IO.FileSystemInfo]'
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Path)
    [long]$bytes = 0
    while ($pending.Count -gt 0) {
        $current = Get-Item -LiteralPath $pending.Pop() -Force -ErrorAction Stop
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
        if ($current.CreationTimeUtc -ge $CutoffUtc -or $current.LastWriteTimeUtc -ge $CutoffUtc) { return }
        $entries.Add($current)
        if ($entries.Count -gt $MaximumEntriesPerDirectory) { throw 'ScanLimitExceeded' }
        if ($current.PSIsContainer) {
            foreach ($child in @(Get-ChildItem -LiteralPath $current.FullName -Force -ErrorAction Stop)) {
                $pending.Push($child.FullName)
            }
        }
        else { $bytes += $current.Length }
    }
    [pscustomobject]@{ Path = $Path; Bytes = $bytes; Entries = $entries }
}

function Get-CacheInventory {
    Assert-CachePath -Path $CacheRoot
    foreach ($directory in @(Get-ChildItem -LiteralPath $CacheRoot -Directory -Force -ErrorAction Stop)) {
        if ($directory.Name -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}_[0-9]+$') { continue }
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        Get-StaleCacheTree -Path $directory.FullName
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 7 -or $MinimumReclaimMB -lt 1 -or $MaximumEntriesPerDirectory -lt 1) { throw 'InvalidConfiguration' }
    $CacheRoot = [IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'IMECache')).TrimEnd('\')
    $CutoffUtc = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    if (-not (Test-Path -LiteralPath $CacheRoot -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | IMECache=Missing' }
    $candidates = @(Get-CacheInventory)
    [long]$eligibleBytes = ($candidates | Measure-Object -Property Bytes -Sum).Sum
    $summary = 'Candidates={0}; EligibleMB={1}; MinimumAgeDays={2}; ThresholdMB={3}' -f $candidates.Count, [math]::Floor($eligibleBytes / 1MB), $MinimumAgeDays, $MinimumReclaimMB
    if ($eligibleBytes -ge ($MinimumReclaimMB * 1MB)) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error | Reason=ScanFailed; Type={0}' -f $_.Exception.GetType().Name) }
