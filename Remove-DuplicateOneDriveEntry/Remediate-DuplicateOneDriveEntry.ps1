<#
.SYNOPSIS
  Remediation script for duplicate OneDrive entries in the File Explorer navigation pane.

.DESCRIPTION
  Finds OneDrive entries that are registered more than once in the File Explorer desktop namespace, keeps the entry that points to an existing folder and removes the remaining per-user registrations after a registry backup. Exits 0 if one entry is left, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$NamePattern = '^OneDrive'
$ReportMachineEntries = $true
$RemoveDuplicate = $true
$BackupBeforeChange = $true

$PackageName = 'DuplicateOneDriveEntry'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-ClsidName { param([string]$Clsid)
    foreach ($root in @("HKCU:\Software\Classes\CLSID\$Clsid", "HKLM:\SOFTWARE\Classes\CLSID\$Clsid")) {
        $value = (Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue).'(default)'
        if ($value) { return [string]$value }
    }
    return $null
}

function Get-OneDriveEntry { param([string]$RootPath, [string]$Hive)
    if (-not (Test-Path -LiteralPath $RootPath)) { return }

    foreach ($key in @(Get-ChildItem -LiteralPath $RootPath -ErrorAction SilentlyContinue)) {
        $clsid = $key.PSChildName
        $name  = [string](Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).'(default)'
        if (-not $name) { $name = [string](Get-ClsidName -Clsid $clsid) }
        if (-not $name) { continue }
        if ($name -notmatch $NamePattern) { continue }

        if ($Hive -eq 'HKCU') { $classesRoot = "HKCU:\Software\Classes\CLSID\$clsid" }
        else { $classesRoot = "HKLM:\SOFTWARE\Classes\CLSID\$clsid" }

        $target = $null
        $rawTarget = (Get-ItemProperty -LiteralPath (Join-Path $classesRoot 'Instance\InitPropertyBag') -Name 'TargetFolderPath' -ErrorAction SilentlyContinue).TargetFolderPath
        if ($rawTarget) { $target = [Environment]::ExpandEnvironmentVariables([string]$rawTarget) }

        $targetExists = $false
        if ($target) { $targetExists = Test-Path -LiteralPath $target }

        $pinnedValue = (Get-ItemProperty -LiteralPath $classesRoot -Name 'System.IsPinnedToNameSpaceTree' -ErrorAction SilentlyContinue).'System.IsPinnedToNameSpaceTree'
        $pinned = $false
        if ($pinnedValue) { $pinned = ([int]$pinnedValue -ne 0) }

        [pscustomobject]@{
            Name              = $name.Trim()
            Hive              = $Hive
            Clsid             = $clsid
            KeyPath           = $key.PSPath
            TargetExists      = $targetExists
            Pinned            = $pinned
            MachineRegistered = (Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\CLSID\$clsid")
        }
    }
}

function Get-OneDriveEntryState {
    $items = @(Get-OneDriveEntry -RootPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace' -Hive 'HKCU')
    if ($ReportMachineEntries) {
        $items += @(Get-OneDriveEntry -RootPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace' -Hive 'HKLM')
    }
    return $items
}

function Get-DuplicateGroup {
    param([object[]]$Entries)

    $groups = @{}
    foreach ($entry in $Entries) {
        $groupKey = $entry.Name.ToLowerInvariant()
        if (-not $groups.ContainsKey($groupKey)) { $groups[$groupKey] = @() }
        $groups[$groupKey] = @($groups[$groupKey]) + $entry
    }

    $result = @()
    foreach ($groupKey in @($groups.Keys)) {
        if (@($groups[$groupKey]).Count -gt 1) { $result += ,@($groups[$groupKey]) }
    }
    return $result
}

function Backup-NameSpaceKey {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    foreach ($root in @((Join-Path $env:ProgramData 'IntuneRemediations\Backup'), (Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'))) {
        try {
            if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null }
            $file = Join-Path $root "OneDriveNameSpace_$stamp.reg"
            & reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace' $file /y | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $file)) { return $file }
        }
        catch { continue }
    }
    return $null
}

try {
    $entries = @(Get-OneDriveEntryState)
    if ($entries.Count -eq 0) { Exit-Script 0 'NotApplicable | OneDriveEntries=0' }

    $duplicateGroups = @(Get-DuplicateGroup -Entries $entries)
    if ($duplicateGroups.Count -eq 0) { Exit-Script 0 "Healthy | OneDriveEntries=$($entries.Count); Duplicates=0" }

    $duplicateCount = 0
    foreach ($group in $duplicateGroups) { $duplicateCount += $group.Count }

    if (-not $RemoveDuplicate) {
        Exit-Script 1 "ReportOnly | OneDriveEntries=$($entries.Count); DuplicateEntries=$duplicateCount; RemoveDuplicate=False"
    }

    $backupFile = $null
    if ($BackupBeforeChange) {
        $backupFile = Backup-NameSpaceKey
        if (-not $backupFile) { Exit-Script 1 'Failed | Reason=BackupFailed' }
        Write-IRTLog "Backup written to $backupFile"
    }

    $removed = 0
    $blocked = 0
    foreach ($group in $duplicateGroups) {
        $scored = @()
        foreach ($entry in $group) {
            $score = 0
            if ($entry.TargetExists) { $score += 8 }
            if ($entry.MachineRegistered) { $score += 4 }
            if ($entry.Pinned) { $score += 2 }
            if ($entry.Hive -eq 'HKCU') { $score += 1 }
            $scored += [pscustomobject]@{ Entry = $entry; Score = $score }
        }

        $ordered = @($scored | Sort-Object -Property Score -Descending)
        $keeper  = $ordered[0].Entry
        Write-IRTLog "Keeping $($keeper.Name) in $($keeper.Hive) with CLSID $($keeper.Clsid)"

        for ($i = 1; $i -lt $ordered.Count; $i++) {
            $entry = $ordered[$i].Entry
            if ($entry.Hive -ne 'HKCU') {
                $blocked++
                Write-IRTLog "Machine entry left alone: $($entry.Clsid)" 'WARN'
                continue
            }
            try {
                Remove-Item -LiteralPath $entry.KeyPath -Recurse -Force -ErrorAction Stop
                $removed++
                Write-IRTLog "Removed namespace entry $($entry.Clsid)"
            }
            catch {
                Write-IRTLog "Remove $($entry.Clsid): $($_.Exception.Message)" 'ERROR'
            }
        }
    }

    $after = @(Get-OneDriveEntryState)
    $left  = @(Get-DuplicateGroup -Entries $after)

    $backupState = 'No'
    if ($backupFile) { $backupState = 'Yes' }

    if ($left.Count -eq 0) {
        Exit-Script 0 "Fixed | Removed=$removed; OneDriveEntries=$($after.Count); Blocked=$blocked; Backup=$backupState"
    }
    Exit-Script 1 "Failed | Removed=$removed; OneDriveEntries=$($after.Count); DuplicateGroups=$($left.Count); Blocked=$blocked"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
