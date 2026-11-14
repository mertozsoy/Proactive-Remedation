<#
.SYNOPSIS
  Remediation script for orphaned folders under the user profiles root.

.DESCRIPTION
  Removes folders under the profiles directory that have no ProfileList entry, are not loaded and are older than $MinAgeDays. Set $RemoveFolders to $false to run a report only pass.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RemoveFolders = $false
$MinAgeDays    = 7

$ExcludeNames = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0')

$PackageName = 'OrphanedUserFolders'
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
    if ($orphans.Count -eq 0) { Exit-Script 0 "Healthy | OrphanFolders=0" }

    if (-not $RemoveFolders) {
        $names = ($orphans | ForEach-Object { $_.Name }) -join ','
        Exit-Script 1 "ReportOnly | WouldRemove=$($orphans.Count); Folders=$names"
    }

    $removed = @()
    $failed  = @()
    foreach ($item in $orphans) {
        $done = $false
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            try {
                Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction Stop
                $done = $true
                break
            }
            catch {
                if ($attempt -eq 1) { Start-Sleep -Seconds 2 }
                else { Write-IRTLog "Failed $($item.Path): $($_.Exception.Message)" 'ERROR' }
            }
        }

        if ($done -and -not (Test-Path -LiteralPath $item.Path)) {
            $removed += $item.Name
            Write-IRTLog "Removed $($item.Path) age $($item.AgeDays) days"
        }
        else {
            $failed += $item.Name
        }
    }

    if ($failed.Count -gt 0) {
        Exit-Script 1 "Failed | Removed=$($removed.Count); Failed=$($failed.Count); Folders=$(($failed) -join ',')"
    }
    Exit-Script 0 "Fixed | Removed=$($removed.Count); Folders=$(($removed) -join ',')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
