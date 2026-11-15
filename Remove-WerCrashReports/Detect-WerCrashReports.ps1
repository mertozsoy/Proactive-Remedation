<#
.SYNOPSIS
  Detection script for Windows Error Reporting queues and crash dump folders that grow on the system drive.

.DESCRIPTION
  Measures the WER report queue and archive plus the CrashDumps folder of every local profile. Exits 1 if the total size or the share of items older than the age limit is over the limit, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SizeLimitMB         = 1024
$ExpiredSizeLimitMB  = 256
$MinAgeDays          = 7
$IncludeUserProfiles = $true

$PackageName = 'WerCrashReports'
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

$WerRoot         = Join-Path $env:ProgramData 'Microsoft\Windows\WER'
$ProfileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

function Format-Size { param([double]$Bytes)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1GB) { return ([string]::Format($inv, '{0:N1}GB', ($Bytes / 1GB))) }
    if ($Bytes -ge 1MB) { return ([string]::Format($inv, '{0:N0}MB', ($Bytes / 1MB))) }
    if ($Bytes -ge 1KB) { return ([string]::Format($inv, '{0:N0}KB', ($Bytes / 1KB))) }
    return ([string]::Format($inv, '{0}B', $Bytes))
}

function Get-TargetFolder {
    $targets = @()
    foreach ($name in @('ReportQueue', 'ReportArchive')) {
        $targets += (Join-Path $WerRoot $name)
    }
    $targets += (Join-Path $env:windir 'System32\Config\SystemProfile\AppData\Local\CrashDumps')

    if ($IncludeUserProfiles) {
        foreach ($key in @(Get-ChildItem -LiteralPath $ProfileListRoot -ErrorAction SilentlyContinue)) {
            $profilePath = (Get-ItemProperty -LiteralPath $key.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
            if (-not $profilePath) { continue }
            $profilePath = [System.Environment]::ExpandEnvironmentVariables($profilePath)
            if (-not [System.IO.Path]::IsPathRooted($profilePath)) { continue }
            $targets += (Join-Path $profilePath 'AppData\Local\CrashDumps')
        }
    }

    $seen = @{}
    foreach ($target in $targets) {
        try { $full = [System.IO.Path]::GetFullPath($target) } catch { continue }
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        if (Test-Path -LiteralPath $full -PathType Container) { $full }
    }
}

function Get-FolderBytes { param([string]$Path)
    $sum = 0
    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)) { $sum += $child.Length }
    $sum
}

function Get-WerFootprint {
    $paths       = @(Get-TargetFolder)
    $totalBytes  = 0
    $fileCount   = 0
    $expiredSize = 0
    $expiredCount = 0
    $cutoff      = (Get-Date).AddDays(-1 * $MinAgeDays)

    foreach ($path in $paths) {
        foreach ($file in @(Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue)) {
            $totalBytes += $file.Length
            $fileCount++
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)) {
            if ($item.LastWriteTime -ge $cutoff) { continue }
            if ($item.PSIsContainer) { $expiredSize += (Get-FolderBytes -Path $item.FullName) }
            else { $expiredSize += $item.Length }
            $expiredCount++
        }
    }

    [pscustomobject]@{
        Targets      = $paths.Count
        TotalBytes   = $totalBytes
        FileCount    = $fileCount
        ExpiredBytes = $expiredSize
        ExpiredCount = $expiredCount
    }
}

try {
    $footprint = Get-WerFootprint
    if ($footprint.Targets -eq 0) { Exit-Script 0 'NotApplicable | WER folders and CrashDumps folders not found' }

    $summary = 'Total={0}; Files={1}; Expired={2}; ExpiredItems={3}; Folders={4}' -f (Format-Size $footprint.TotalBytes), $footprint.FileCount, (Format-Size $footprint.ExpiredBytes), $footprint.ExpiredCount, $footprint.Targets
    Write-IRTLog $summary

    $reasons = @()
    if ($footprint.TotalBytes -ge ($SizeLimitMB * 1MB)) { $reasons += 'TotalOver' }
    if ($footprint.ExpiredBytes -ge ($ExpiredSizeLimitMB * 1MB)) { $reasons += 'ExpiredOver' }

    if ($reasons.Count -gt 0) { Exit-Script 1 ('Drift | {0}; Reason={1}' -f $summary, ($reasons -join '+')) }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
