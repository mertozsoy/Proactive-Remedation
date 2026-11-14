<#
.SYNOPSIS
  Remediation script that removes old Intune Win32 application cache content.

.DESCRIPTION
  Removes eligible GUID_version directories from Windows IMECache after checking
  retention, process activity and reparse points. Deletes files individually and
  directories only when empty. Exits 0 after verification, 1 if deferred or failed.
  Does not touch Incoming, Staging, application state, user profiles or services.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumAgeDays = 30
$MinimumReclaimMB = 512
$MaximumEntriesPerDirectory = 50000
$EnableCleanup = $true
$BusyProcessNames = @('msiexec.exe', 'setup.exe', 'setuphost.exe', 'winget.exe', 'AppInstallerCLI.exe')

$PackageName = 'OldIMECache'
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

function Test-CacheBusy {
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Property Name, ExecutablePath, CommandLine -ErrorAction Stop)) {
        if ($BusyProcessNames -contains $process.Name) { return $true }
        if ($process.ExecutablePath -and $process.ExecutablePath.IndexOf($CacheRoot + '\', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        if ($process.CommandLine -and $process.CommandLine.IndexOf($CacheRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Remove-StaleCacheTree { param($Tree)
    foreach ($entry in @($Tree.Entries | Where-Object { -not $_.PSIsContainer })) {
        Assert-CachePath -Path $entry.FullName
        $fresh = Get-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop
        if ($fresh.PSIsContainer -or $fresh.CreationTimeUtc -ge $CutoffUtc -or $fresh.LastWriteTimeUtc -ge $CutoffUtc -or $fresh.Length -ne $entry.Length) {
            throw 'ContentChanged'
        }
        $stream = [IO.File]::Open($fresh.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        $stream.Dispose()
        Remove-Item -LiteralPath $fresh.FullName -Force -ErrorAction Stop
    }
    foreach ($directory in @($Tree.Entries | Where-Object { $_.PSIsContainer } | Sort-Object { $_.FullName.Length } -Descending)) {
        Assert-CachePath -Path $directory.FullName
        [IO.Directory]::Delete($directory.FullName, $false)
    }
    if (Test-Path -LiteralPath $Tree.Path -ErrorAction Stop) { throw 'DeletionNotVerified' }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($MinimumAgeDays -lt 7 -or $MinimumReclaimMB -lt 1 -or $MaximumEntriesPerDirectory -lt 1) { throw 'InvalidConfiguration' }
    $CacheRoot = [IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'IMECache')).TrimEnd('\')
    $CutoffUtc = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    if (-not (Test-Path -LiteralPath $CacheRoot -ErrorAction Stop)) { Exit-Script 0 'NotApplicable | IMECache=Missing' }
    $candidates = @(Get-CacheInventory)
    [long]$eligibleBytes = ($candidates | Measure-Object -Property Bytes -Sum).Sum
    if ($eligibleBytes -lt ($MinimumReclaimMB * 1MB)) { Exit-Script 0 'Healthy | CleanupRequired=False' }
    if (-not $EnableCleanup) { Exit-Script 1 ('Deferred | Reason=CleanupDisabled; Candidates={0}' -f $candidates.Count) }
    if (Test-CacheBusy) { Exit-Script 1 'Deferred | Reason=InstallerActivity; Removed=0' }
    $removed = 0
    $failed = 0
    [long]$removedBytes = 0
    foreach ($candidate in $candidates) {
        if (Test-CacheBusy) { Exit-Script 1 "Deferred | Reason=InstallerActivity; Removed=$removed" }
        try {
            $tree = Get-StaleCacheTree -Path $candidate.Path
            if ($null -eq $tree) { $failed++; continue }
            Remove-StaleCacheTree -Tree $tree
            $removed++
            $removedBytes += $tree.Bytes
        }
        catch {
            $failed++
            Write-IRTLog ('CleanupFailed | Type={0}' -f $_.Exception.GetType().Name) 'WARN'
        }
    }
    $remaining = @(Get-CacheInventory)
    [long]$remainingBytes = ($remaining | Measure-Object -Property Bytes -Sum).Sum
    $summary = 'Removed={0}; RemovedContentMB={1}; Failed={2}; RemainingEligibleMB={3}' -f $removed, [math]::Floor($removedBytes / 1MB), $failed, [math]::Floor($remainingBytes / 1MB)
    if ($failed -gt 0 -or $remainingBytes -ge ($MinimumReclaimMB * 1MB)) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 ('Error | Reason=CleanupFailed; Type={0}' -f $_.Exception.GetType().Name) }
