<#
.SYNOPSIS
  Remediation script for missing or broken Office and Edge Start menu shortcuts.

.DESCRIPTION
  Backs up and repairs shortcuts whose target or icon no longer exists and creates missing shortcuts in the all users Start menu. Re-scans every profile afterwards and exits 0 only when each Office and Edge app has a working shortcut.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetApps = @(
    @{ Name = 'Word'; Title = 'Word'; Exe = 'WINWORD.EXE' },
    @{ Name = 'Excel'; Title = 'Excel'; Exe = 'EXCEL.EXE' },
    @{ Name = 'Outlook'; Title = 'Outlook'; Exe = 'OUTLOOK.EXE' },
    @{ Name = 'PowerPoint'; Title = 'PowerPoint'; Exe = 'POWERPNT.EXE' },
    @{ Name = 'Edge'; Title = 'Microsoft Edge'; Exe = 'MSEDGE.EXE' }
)
$HealthyStates = @('Healthy', 'Advertised')
$CreateMissingShortcuts = $true
$RepairBrokenShortcuts  = $true
$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup\Shortcuts'

$PackageName = 'OfficeEdgeShortcuts'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Resolve-AppExecutable {
    param([string]$ExeName)
    $candidates = @()
    foreach ($key in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExeName", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$ExeName")) {
        $value = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).'(default)'
        if ($value) { $candidates += ([string]$value).Trim().Trim('"') }
    }
    $officeRoots = @()
    if ($env:ProgramFiles) { $officeRoots += (Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16') }
    if (${env:ProgramFiles(x86)}) { $officeRoots += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\root\Office16') }
    foreach ($root in $officeRoots) { $candidates += (Join-Path $root $ExeName) }
    $edgeRoots = @()
    if (${env:ProgramFiles(x86)}) { $edgeRoots += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application') }
    if ($env:ProgramFiles) { $edgeRoots += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application') }
    foreach ($root in $edgeRoots) { $candidates += (Join-Path $root $ExeName) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-StartMenuRoot {
    $roots = @()
    $common = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    if (Test-Path -LiteralPath $common -PathType Container) { $roots += [pscustomobject]@{ Scope = 'AllUsers'; Path = $common } }
    $skipped = @('systemprofile', 'localservice', 'networkservice', 'default', 'default user', 'public', 'all users')
    foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue)) {
        $imagePath = (Get-ItemProperty -LiteralPath $key.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $imagePath) { continue }
        $imagePath = [Environment]::ExpandEnvironmentVariables([string]$imagePath)
        $leaf = (Split-Path -Leaf $imagePath).ToLowerInvariant()
        if ($skipped -contains $leaf) { continue }
        $programs = Join-Path $imagePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
        if (Test-Path -LiteralPath $programs -PathType Container) { $roots += [pscustomobject]@{ Scope = 'User'; Path = $programs } }
    }
    return $roots
}

function Get-ShortcutEntry {
    param($Shell, $Roots)
    $entries = @()
    foreach ($root in $Roots) {
        foreach ($file in @(Get-ChildItem -LiteralPath $root.Path -Filter '*.lnk' -Recurse -Force -ErrorAction SilentlyContinue)) {
            $state = 'Healthy'
            $targetLeaf = ''
            $iconPath = ''
            if ($file.Length -eq 0) { $state = 'EmptyShortcut' }
            else {
                $link = $null
                try { $link = $Shell.CreateShortcut($file.FullName) } catch { $link = $null }
                if (-not $link) { $state = 'Unreadable' }
                else {
                    if ($link.IconLocation) { $iconPath = [Environment]::ExpandEnvironmentVariables((($link.IconLocation -split ',')[0]).Trim().Trim('"')) }
                    if ($link.TargetPath) {
                        $targetLeaf = (Split-Path -Leaf $link.TargetPath).ToUpperInvariant()
                        if (-not (Test-Path -LiteralPath $link.TargetPath -PathType Leaf)) { $state = 'TargetMissing' }
                        elseif ($iconPath -and -not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { $state = 'IconMissing' }
                    }
                    elseif ($iconPath -and (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
                        $targetLeaf = (Split-Path -Leaf $iconPath).ToUpperInvariant()
                        $state = 'Advertised'
                    }
                    else { $state = 'NoTarget' }
                }
            }
            $entries += [pscustomobject]@{ Scope = $root.Scope; Root = $root.Path; Path = $file.FullName; State = $state; TargetLeaf = $targetLeaf }
        }
    }
    return $entries
}

function Get-AppState {
    param([string]$ExeName, $Entries, $Roots)
    $found = @($Entries | Where-Object { $_.TargetLeaf -eq $ExeName })
    if ($found.Count -eq 0) { return 'Missing' }
    $healthy = @($found | Where-Object { $HealthyStates -contains $_.State })
    $broken = @($found | Where-Object { $HealthyStates -notcontains $_.State })
    if ($healthy.Count -eq 0) { return 'Broken' }
    if ($broken.Count -gt 0) { return 'Duplicate' }
    if (@($healthy | Where-Object { $_.Scope -eq 'AllUsers' }).Count -gt 0) { return 'OK' }
    foreach ($root in @($Roots | Where-Object { $_.Scope -eq 'User' })) {
        if (@($healthy | Where-Object { $_.Root -eq $root.Path }).Count -eq 0) { return 'Partial' }
    }
    return 'OK'
}

function Get-EntryExeName {
    param($Entry, $Executables)
    if ($Entry.TargetLeaf) {
        if ($Executables.ContainsKey($Entry.TargetLeaf)) { return $Entry.TargetLeaf }
        return $null
    }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Entry.Path)
    foreach ($app in $TargetApps) {
        if ($base -eq $app.Title) { return $app.Exe }
    }
    return $null
}

function Backup-Shortcut {
    param([string]$Path, [string]$BackupDir, [ref]$Counter)
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force -ErrorAction Stop | Out-Null }
    $Counter.Value = [int]$Counter.Value + 1
    $destination = Join-Path $BackupDir ('{0}_{1}' -f $Counter.Value, (Split-Path -Leaf $Path))
    Copy-Item -LiteralPath $Path -Destination $destination -Force -ErrorAction Stop
    return $destination
}

function New-AppShortcut {
    param($Shell, [string]$TargetPath, [string]$LinkPath, [string]$Title)
    $link = $Shell.CreateShortcut($LinkPath)
    $link.TargetPath = $TargetPath
    $link.WorkingDirectory = Split-Path -Parent $TargetPath
    $link.IconLocation = "$TargetPath,0"
    $link.Description = $Title
    $link.Save()
}

function Repair-Shortcut {
    param($Shell, [string]$Path, [string]$TargetPath, [string]$Title, [string]$BackupDir, [ref]$Counter)
    Backup-Shortcut -Path $Path -BackupDir $BackupDir -Counter $Counter | Out-Null
    $link = $null
    try { $link = $Shell.CreateShortcut($Path) } catch { $link = $null }
    if ($link -and $link.TargetPath -and (Test-Path -LiteralPath $link.TargetPath -PathType Leaf)) {
        $link.IconLocation = "$TargetPath,0"
        $link.Save()
    }
    else {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        New-AppShortcut -Shell $Shell -TargetPath $TargetPath -LinkPath $Path -Title $Title
    }
}

try {
    $shell = New-Object -ComObject WScript.Shell
    $roots = @(Get-StartMenuRoot)
    if ($roots.Count -eq 0) { Exit-Script 0 'NotApplicable | NoStartMenuFolders' }
    $allUsersRoot = ($roots | Where-Object { $_.Scope -eq 'AllUsers' } | Select-Object -First 1).Path

    $executables = @{}
    foreach ($app in $TargetApps) {
        $exePath = Resolve-AppExecutable -ExeName $app.Exe
        if ($exePath) { $executables[$app.Exe] = $exePath }
    }

    $actions = @()
    $backupIndex = 0
    $backupDir = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')

    if ($RepairBrokenShortcuts) {
        $entries = @(Get-ShortcutEntry -Shell $shell -Roots $roots)
        foreach ($entry in @($entries | Where-Object { $HealthyStates -notcontains $_.State })) {
            $exeName = Get-EntryExeName -Entry $entry -Executables $executables
            if (-not $exeName) { continue }
            $title = ($TargetApps | Where-Object { $_.Exe -eq $exeName } | Select-Object -First 1).Title
            try {
                Repair-Shortcut -Shell $shell -Path $entry.Path -TargetPath $executables[$exeName] -Title $title -BackupDir $backupDir -Counter ([ref]$backupIndex)
                $actions += ('{0}=ShortcutRepaired' -f $title)
                Write-IRTLog "Repaired shortcut $($entry.Path)"
            }
            catch {
                $actions += ('{0}=RepairError' -f $title)
                Write-IRTLog "Repair $($entry.Path): $($_.Exception.Message)" 'ERROR'
            }
        }
    }

    $entries = @(Get-ShortcutEntry -Shell $shell -Roots $roots)
    foreach ($app in $TargetApps) {
        if (-not $executables.ContainsKey($app.Exe)) { continue }
        $state = Get-AppState -ExeName $app.Exe -Entries $entries -Roots $roots
        if ($state -eq 'OK') { continue }
        if (-not $CreateMissingShortcuts) { $actions += ('{0}={1}' -f $app.Name, $state); continue }
        if (-not $allUsersRoot) { $actions += ('{0}=NoAllUsersFolder' -f $app.Name); continue }
        $linkPath = Join-Path $allUsersRoot ($app.Title + '.lnk')
        try {
            if (Test-Path -LiteralPath $linkPath) { Backup-Shortcut -Path $linkPath -BackupDir $backupDir -Counter ([ref]$backupIndex) | Out-Null }
            New-AppShortcut -Shell $shell -TargetPath $executables[$app.Exe] -LinkPath $linkPath -Title $app.Title
            $actions += ('{0}=ShortcutCreated' -f $app.Name)
            Write-IRTLog "Created shortcut $linkPath for state $state"
        }
        catch {
            $actions += ('{0}=CreateError' -f $app.Name)
            Write-IRTLog "Create shortcut failed: $linkPath | $($_.Exception.Message)" 'ERROR'
        }
    }

    $entries = @(Get-ShortcutEntry -Shell $shell -Roots $roots)
    $states = @()
    foreach ($app in $TargetApps) {
        if (-not $executables.ContainsKey($app.Exe)) { $states += ('{0}=NotInstalled' -f $app.Name); continue }
        $states += ('{0}={1}' -f $app.Name, (Get-AppState -ExeName $app.Exe -Entries $entries -Roots $roots))
    }
    $summary = $states -join '; '
    $actionsText = ''
    if ($actions.Count -gt 0) { $actionsText = '; Actions=' + (($actions | Select-Object -Unique) -join ',') }
    $faults = @($states | Where-Object { $_ -notmatch '=(OK|NotInstalled)$' })
    if ($faults.Count -eq 0) {
        if ($actions.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
        Exit-Script 0 "Fixed | $summary$actionsText"
    }
    Exit-Script 1 "Failed | $summary$actionsText"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
