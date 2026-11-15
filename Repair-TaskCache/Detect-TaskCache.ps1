<#
.SYNOPSIS
  Detection script for orphaned Task Scheduler cache entries.

.DESCRIPTION
  Compares TaskCache records with task files and checks scheduler enumeration.
  Exits 1 for missing files, inconsistent records or enumeration failures, otherwise 0.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProtectedTaskPrefixes = @('\Microsoft\')

$PackageName = 'TaskCache'
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
function Get-CacheState {
    $treeRoot = Join-Path $CacheRoot 'Tree'
    $tasksRoot = Join-Path $CacheRoot 'Tasks'
    $treeBase = (Get-Item -LiteralPath $treeRoot -ErrorAction Stop).Name
    $treeMap = @{}
    $review = 0
    $orphans = @()
    foreach ($key in @(Get-ChildItem -LiteralPath $treeRoot -Recurse -ErrorAction Stop)) {
        $id = [string]$key.GetValue('Id')
        if (-not $id) { continue }
        if (-not $treeMap.ContainsKey($id)) { $treeMap[$id] = @() }
        $treeMap[$id] += $key.Name.Substring($treeBase.Length + 1)
    }
    $seen = @{}
    foreach ($key in @(Get-ChildItem -LiteralPath $tasksRoot -ErrorAction Stop)) {
        $id = $key.PSChildName
        $seen[$id] = $true
        $taskPath = [string]$key.GetValue('Path')
        if ($id -notmatch '^\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}$' -or
            $taskPath -notmatch '^\\[^\\]' -or $taskPath -match '[/:*?"<>|]' -or
            @($taskPath.Split('\') | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            $review++
            continue
        }
        $relative = $taskPath.TrimStart('\')
        if (-not $treeMap.ContainsKey($id) -or $treeMap[$id].Count -ne 1 -or $treeMap[$id][0] -ne $relative) {
            $review++
            continue
        }
        $file = Join-Path $TaskFiles $relative
        if (Test-Path -LiteralPath $file -ErrorAction Stop) { continue }
        $protected = @($ProtectedTaskPrefixes | Where-Object { $taskPath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        $treeKey = Join-Path $treeRoot $relative
        if (@(Get-ChildItem -LiteralPath $treeKey -ErrorAction Stop).Count -gt 0) { $review++; continue }
        Write-IRTLog "OrphanId=$id; Protected=$protected"
        $orphans += [pscustomobject]@{ Id = $id; TreeKey = $treeKey; TaskKey = $key.PSPath; Protected = $protected }
    }
    foreach ($id in $treeMap.Keys) { if (-not $seen.ContainsKey($id)) { $review++ } }
    [pscustomobject]@{ Orphans = $orphans; Review = $review }
}
try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $CacheRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache'
    $TaskFiles = Join-Path $env:SystemRoot 'System32\Tasks'
    if (-not (Test-Path -LiteralPath $CacheRoot)) { Exit-Script 1 'Failed | Reason=TaskCacheMissing' }
    if (-not (Test-Path -LiteralPath $TaskFiles -PathType Container)) { Exit-Script 1 'Failed | Reason=TaskDirectoryMissing' }
    $state = Get-CacheState
    $enumeration = 'OK'
    try { $null = @(Get-ScheduledTask -ErrorAction Stop) } catch { $enumeration = 'Failed' }
    if ($state.Orphans.Count -gt 0 -or $state.Review -gt 0 -or $enumeration -ne 'OK') {
        Exit-Script 1 "Drift | Orphans=$($state.Orphans.Count); Review=$($state.Review); Enumeration=$enumeration"
    }
    Exit-Script 0 'Healthy | Orphans=0; Review=0; Enumeration=OK'
}
catch { Exit-Script 1 "Error: | HResult=$($_.Exception.HResult)" }
