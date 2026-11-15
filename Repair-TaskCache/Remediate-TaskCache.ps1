<#
.SYNOPSIS
  Remediation script for approved orphaned Task Scheduler cache entries.

.DESCRIPTION
  Backs up TaskCache and task files before deleting approved cache records whose
  task files are absent. Cleanup is disabled by default. Verifies cache and API health.
  Exits 0 only when verification succeeds, otherwise 1. Does not recreate tasks.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$ApprovedOrphanIds = @()
$ProtectedTaskPrefixes = @('\Microsoft\')
$MaxRemovals = 5

$PackageName = 'TaskCache'
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
    $targets = @($state.Orphans | Where-Object { -not $_.Protected -and $ApprovedOrphanIds -contains $_.Id })
    $removed = 0
    if ($state.Orphans.Count -gt 0 -and -not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Orphans=$($state.Orphans.Count); Review=$($state.Review); CleanupEnabled=False"
    }
    if ($targets.Count -gt $MaxRemovals -or $MaxRemovals -lt 1) { Exit-Script 1 'Blocked | Reason=RemovalLimit' }
    if ($targets.Count -gt 0) {
        $backup = Join-Path $env:ProgramData ('IntuneRemediations\Backup\TaskCache\' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $backup -ItemType Directory -Force -ErrorAction Stop
        $acl = Get-Acl -LiteralPath $backup -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sidText in @('S-1-5-18', 'S-1-5-32-544')) {
            $sid = New-Object System.Security.Principal.SecurityIdentifier($sidText)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $backup -AclObject $acl -ErrorAction Stop
        $regFile = Join-Path $backup 'TaskCache.reg'
        $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
        $null = & $reg export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache' $regFile /y 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $regFile)) { throw 'Registry backup failed' }
        Copy-Item -LiteralPath $TaskFiles -Destination (Join-Path $backup 'Tasks') -Recurse -Force -ErrorAction Stop
        Write-IRTLog 'Backup=Complete'
        foreach ($target in $targets) {
            $fresh = @( (Get-CacheState).Orphans | Where-Object { $_.Id -eq $target.Id -and -not $_.Protected })
            if ($fresh.Count -ne 1 -or $fresh[0].TreeKey -ne $target.TreeKey) { throw 'Cache changed during repair' }
            $keys = @($target.TreeKey, $target.TaskKey)
            foreach ($index in @('Plain', 'Logon', 'Boot')) {
                $indexKey = Join-Path (Join-Path $CacheRoot $index) $target.Id
                if (Test-Path -LiteralPath $indexKey) { $keys += $indexKey }
            }
            foreach ($key in $keys) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop }
            foreach ($key in $keys) { if (Test-Path -LiteralPath $key) { throw 'Cache deletion verification failed' } }
            $removed++
            Write-IRTLog "RemovedId=$($target.Id)"
        }
    }
    $after = Get-CacheState
    $enumeration = 'OK'
    try { $null = @(Get-ScheduledTask -ErrorAction Stop) } catch { $enumeration = 'Failed' }
    if ($after.Orphans.Count -gt 0 -or $after.Review -gt 0 -or $enumeration -ne 'OK') {
        Exit-Script 1 "Failed | Removed=$removed; Orphans=$($after.Orphans.Count); Review=$($after.Review); Enumeration=$enumeration"
    }
    Exit-Script 0 "Fixed | Removed=$removed; Orphans=0; Review=0; Enumeration=OK"
}
catch { Exit-Script 1 "Error: | HResult=$($_.Exception.HResult)" }
