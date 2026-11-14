<#
.SYNOPSIS
  Remediation script that removes orphaned uninstall registry entries left by removed applications.

.DESCRIPTION
  Finds uninstall entries whose uninstall executable and install folder are both missing, exports each key with reg export,
  deletes the key and rescans. Exits 0 when no orphan entry is left, 1 when the cleanup fails or is turned off.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$IncludeUserHives    = $false
$ExcludedNamePattern = ''
$MaxNamesInOutput    = 5
$EnableRemediation   = $true

$PackageName = 'OrphanUninstallKeys'
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

$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup\OrphanUninstallKeys'
$RegExe     = Join-Path $env:SystemRoot 'System32\reg.exe'

function Get-UninstallRootPath {
    $roots = New-Object System.Collections.ArrayList
    [void]$roots.Add('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    [void]$roots.Add('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    if ($IncludeUserHives) {
        foreach ($sid in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue)) {
            $sidName = $sid.PSChildName
            if ($sidName -match '_Classes$') { continue }
            if ($sidName -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { continue }
            $userRoot = 'Registry::HKEY_USERS\' + $sidName + '\Software\Microsoft\Windows\CurrentVersion\Uninstall'
            if (Test-Path -LiteralPath $userRoot -ErrorAction SilentlyContinue) { [void]$roots.Add($userRoot) }
        }
    }
    $roots
}

function Test-ExistingPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return [bool](Test-Path -LiteralPath $Path -ErrorAction Stop) } catch { return $false }
}

function Get-ExecutablePath {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $text = $Command.Trim()
    $path = $null
    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -gt 1) { $path = $text.Substring(1, $end - 1) }
    }
    else {
        $match = [regex]::Match($text, '^(?<path>.+?\.exe)(\s|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { $path = $match.Groups['path'].Value }
    }
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($path).Trim()
    if ($expanded -notmatch '^[A-Za-z]:\\') { return $null }
    if ($expanded.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) { return $null }
    $expanded
}

function Read-UninstallEntry {
    param([string]$KeyPath)
    $props = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction Stop
    $displayName = [string]$props.DisplayName
    if ([string]::IsNullOrWhiteSpace($displayName)) { return $null }
    [pscustomobject]@{
        KeyPath              = $KeyPath
        RegPath              = ($KeyPath -replace '^.*Registry::', '')
        DisplayName          = $displayName.Trim()
        DisplayVersion       = [string]$props.DisplayVersion
        UninstallString      = [string]$props.UninstallString
        QuietUninstallString = [string]$props.QuietUninstallString
        InstallLocation      = [string]$props.InstallLocation
        SystemComponent      = $props.SystemComponent
        ParentKeyName        = [string]$props.ParentKeyName
        ReleaseType          = [string]$props.ReleaseType
        WindowsInstaller     = $props.WindowsInstaller
    }
}

function Test-GhostEntry {
    param($Entry)
    if ($ExcludedNamePattern -and $Entry.DisplayName -match $ExcludedNamePattern) { return $false }
    if ([string]$Entry.SystemComponent -eq '1') { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Entry.ParentKeyName)) { return $false }
    if ($Entry.ReleaseType -match '^(Update|Hotfix|Security Update|Service Pack|ServicePack|Update Rollup)$') { return $false }
    if ([string]$Entry.WindowsInstaller -eq '1') { return $false }
    $command = $Entry.UninstallString
    if ([string]::IsNullOrWhiteSpace($command)) { $command = $Entry.QuietUninstallString }
    if ([string]::IsNullOrWhiteSpace($command)) { return $false }
    $executable = Get-ExecutablePath -Command $command
    if (-not $executable) { return $false }
    if (Test-ExistingPath -Path $executable) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($Entry.InstallLocation)) {
        $location = [Environment]::ExpandEnvironmentVariables($Entry.InstallLocation.Trim().Trim('"'))
        if (Test-ExistingPath -Path $location) { return $false }
    }
    return $true
}

function Get-GhostEntry {
    $ghosts = New-Object System.Collections.ArrayList
    $scanned = 0
    $unreadable = 0
    foreach ($root in @(Get-UninstallRootPath)) {
        if (-not (Test-ExistingPath -Path $root)) { continue }
        $subKeys = @()
        try { $subKeys = @(Get-ChildItem -LiteralPath $root -ErrorAction Stop) } catch { $unreadable++; continue }
        foreach ($subKey in $subKeys) {
            $keyPath = $root + '\' + $subKey.PSChildName
            $scanned++
            $entry = $null
            try { $entry = Read-UninstallEntry -KeyPath $keyPath } catch { $unreadable++; continue }
            if ($null -eq $entry) { continue }
            if (Test-GhostEntry -Entry $entry) { [void]$ghosts.Add($entry) }
        }
    }
    [pscustomobject]@{ Ghosts = $ghosts; Scanned = $scanned; Unreadable = $unreadable }
}

function Format-GhostList {
    param($Ghosts)
    $names = @()
    foreach ($ghost in @($Ghosts | Select-Object -First $MaxNamesInOutput)) {
        $label = ($ghost.DisplayName -replace '[;|\r\n]', ' ').Trim()
        if ($label.Length -gt 40) { $label = $label.Substring(0, 40) }
        if (-not [string]::IsNullOrWhiteSpace($ghost.DisplayVersion)) { $label = '{0} {1}' -f $label, $ghost.DisplayVersion }
        $names += $label
    }
    $text = $names -join ', '
    if ($Ghosts.Count -gt $MaxNamesInOutput) { $text = $text + ' (+' + ($Ghosts.Count - $MaxNamesInOutput) + ' more)' }
    $text
}

function Save-UninstallKeyBackup {
    param($Entry)
    $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeName = ($Entry.DisplayName -replace '[^A-Za-z0-9.-]', '_')
    if ($safeName.Length -gt 40) { $safeName = $safeName.Substring(0, 40) }
    $file = Join-Path $BackupRoot ('{0}_{1}.reg' -f $stamp, $safeName)
    $index = 1
    while (Test-Path -LiteralPath $file) {
        $file = Join-Path $BackupRoot ('{0}_{1}_{2}.reg' -f $stamp, $safeName, $index)
        $index++
    }
    $arguments = 'export "{0}" "{1}" /y' -f $Entry.RegPath, $file
    $process = Start-Process -FilePath $RegExe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($process.ExitCode -ne 0) { throw "reg export failed with exit code $($process.ExitCode)" }
    if (-not (Test-ExistingPath -Path $file)) { throw 'backup file was not created' }
    $file
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error | Reason=Requires64BitPowerShell' }

    $scan = Get-GhostEntry
    if ($scan.Ghosts.Count -eq 0) {
        Exit-Script 0 "Healthy | GhostKeys=0; Scanned=$($scan.Scanned); Unreadable=$($scan.Unreadable)"
    }

    $names = Format-GhostList -Ghosts $scan.Ghosts
    if (-not $EnableRemediation) {
        Exit-Script 1 "Reported | GhostKeys=$($scan.Ghosts.Count); Entries=$names; Action=EnableRemediation"
    }

    $removed = 0
    $skipped = 0
    $failed = 0
    $backups = 0
    foreach ($ghost in $scan.Ghosts) {
        try {
            $fresh = Read-UninstallEntry -KeyPath $ghost.KeyPath
            if ($null -eq $fresh -or -not (Test-GhostEntry -Entry $fresh)) {
                $skipped++
                Write-IRTLog "Skipped $($ghost.KeyPath): entry changed or is not an orphan"
                continue
            }
            $backupFile = Save-UninstallKeyBackup -Entry $fresh
            $backups++
            Remove-Item -LiteralPath $fresh.KeyPath -Recurse -Force -ErrorAction Stop
            $removed++
            Write-IRTLog "Removed orphan entry: $($fresh.DisplayName) $($fresh.DisplayVersion) | $backupFile"
        }
        catch {
            $failed++
            Write-IRTLog "Failed $($ghost.KeyPath): $($_.Exception.Message)" 'WARN'
        }
    }

    $after = Get-GhostEntry
    if ($failed -gt 0 -or $after.Ghosts.Count -gt 0) {
        Exit-Script 1 "Failed | Removed=$removed; Remaining=$($after.Ghosts.Count); Failed=$failed; Skipped=$skipped; Backup=$BackupRoot"
    }

    Exit-Script 0 "Fixed | Removed=$removed; Remaining=0; Scanned=$($scan.Scanned); Backups=$backups; Entries=$names"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
