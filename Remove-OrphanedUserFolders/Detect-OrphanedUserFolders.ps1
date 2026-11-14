<#
.SYNOPSIS
  Detection script for orphaned folders under the user profiles root.

.DESCRIPTION
  Lists folders under the profiles directory that have no ProfileList entry, are not loaded and are older than $MinAgeDays. Exits 1 if any orphaned folder is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinAgeDays = 7

$ExcludeNames = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0')

$PackageName = 'OrphanedUserFolders'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-ProfilesRoot {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $dir = $null
    try { $dir = (Get-ItemProperty -LiteralPath $key -Name ProfilesDirectory -ErrorAction Stop).ProfilesDirectory } catch { }
    if (-not $dir) { $dir = Join-Path $env:SystemDrive 'Users' }
    [Environment]::ExpandEnvironmentVariables($dir).TrimEnd('\')
}

function Get-ProfilePathSet {
    param([switch]$LoadedOnly)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    if ($LoadedOnly) {
        foreach ($p in (Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue)) {
            if (-not $p.Loaded) { continue }
            if ($p.LocalPath) { [void]$set.Add($p.LocalPath.TrimEnd('\')) }
        }
    }
    else {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        foreach ($sidKey in (Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
            $p = (Get-ItemProperty -LiteralPath $sidKey.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
            if ($p) { [void]$set.Add(([Environment]::ExpandEnvironmentVariables($p)).TrimEnd('\')) }
        }
    }
    $set
}

function Get-OrphanedFolder {
    param([string]$Root, [int]$Days)
    $known  = Get-ProfilePathSet
    $loaded = Get-ProfilePathSet -LoadedOnly
    $cutoff = (Get-Date).AddDays(-$Days)
    foreach ($dir in (Get-ChildItem -LiteralPath $Root -Force -Directory -ErrorAction Stop)) {
        if (($dir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ($ExcludeNames -contains $dir.Name) { continue }
        $full = $dir.FullName.TrimEnd('\')
        if ($known.Contains($full)) { continue }
        if ($loaded.Contains($full)) { continue }
        if ($dir.CreationTime -gt $cutoff) { continue }
        [pscustomobject]@{ Name = $dir.Name; Path = $full; AgeDays = [int]((Get-Date) - $dir.CreationTime).TotalDays }
    }
}

try {
    $root = Get-ProfilesRoot
    if (-not (Test-Path -LiteralPath $root)) { Exit-Script 0 "NotApplicable | ProfilesRoot missing: $root" }

    $orphans = @(Get-OrphanedFolder -Root $root -Days $MinAgeDays)
    if ($orphans.Count -eq 0) { Exit-Script 0 "Healthy | OrphanFolders=0; Root=$root" }

    $shown = $orphans | Sort-Object AgeDays -Descending | Select-Object -First 10
    $list = ($shown | ForEach-Object { '{0}({1}d)' -f $_.Name, $_.AgeDays }) -join ','
    if ($orphans.Count -gt $shown.Count) { $list = $list + ",+$($orphans.Count - $shown.Count)more" }

    Write-IRTLog "Orphaned folders: $(($orphans | ForEach-Object { $_.Path }) -join '; ')"
    Exit-Script 1 "Orphaned | Count=$($orphans.Count); Folders=$list"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
