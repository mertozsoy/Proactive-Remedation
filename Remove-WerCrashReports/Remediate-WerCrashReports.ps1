<#
.SYNOPSIS
  Remediation script that deletes old Windows Error Reporting items and crash dump files.

.DESCRIPTION
  Removes report queue and archive folders plus CrashDumps files that are older than the age limit when the size limit is crossed. Exits 0 if the footprint is back under the limit, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SizeLimitMB         = 1024
$ExpiredSizeLimitMB  = 256
$MinAgeDays          = 7
$IncludeUserProfiles = $true
$RemoveReports       = $true

$PackageName = 'WerCrashReports'
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
        $full = [System.IO.Path]::GetFullPath($target)
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

function Get-ItemBytes { param($Item)
    if (-not $Item.PSIsContainer) { return [int64]$Item.Length }
    Get-FolderBytes -Path $Item.FullName
}

function Get-WerFootprint {
    $paths        = @(Get-TargetFolder)
    $totalBytes   = 0
    $fileCount    = 0
    $expiredSize  = 0
    $expiredCount = 0
    $cutoff       = (Get-Date).AddDays(-1 * $MinAgeDays)

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
    $before = Get-WerFootprint
    if ($before.Targets -eq 0) { Exit-Script 0 'NotApplicable | WER folders and CrashDumps folders not found' }

    $totalLimit   = $SizeLimitMB * 1MB
    $expiredLimit = $ExpiredSizeLimitMB * 1MB
    $overLimit    = ($before.TotalBytes -ge $totalLimit) -or ($before.ExpiredBytes -ge $expiredLimit)

    if (-not $overLimit) {
        $healthy = 'Total={0}; Files={1}; Expired={2}; Folders={3}' -f (Format-Size $before.TotalBytes), $before.FileCount, (Format-Size $before.ExpiredBytes), $before.Targets
        Exit-Script 0 "Healthy | $healthy"
    }

    $beforeText = 'Total={0}; Files={1}; Expired={2}; ExpiredItems={3}; Folders={4}' -f (Format-Size $before.TotalBytes), $before.FileCount, (Format-Size $before.ExpiredBytes), $before.ExpiredCount, $before.Targets
    Write-IRTLog $beforeText

    if (-not $RemoveReports) {
        Exit-Script 1 "Drift | $beforeText; Action=report only"
    }

    $cutoff  = (Get-Date).AddDays(-1 * $MinAgeDays)
    $removed = 0
    $freed   = 0
    $skipped = 0

    foreach ($path in @(Get-TargetFolder)) {
        foreach ($item in @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)) {
            if ($item.LastWriteTime -ge $cutoff) { continue }
            $size = Get-ItemBytes -Item $item
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $removed++
                $freed += $size
                Write-IRTLog ('Removed {0} ({1})' -f $item.FullName, (Format-Size $size))
            }
            catch {
                $skipped++
                Write-IRTLog -Message ('Skip {0}: {1}' -f $item.FullName, $_.Exception.Message) -Level 'WARN'
            }
        }
    }

    $after  = Get-WerFootprint
    $result = 'Removed={0}; Freed={1}; Skipped={2}; Remaining={3}; Files={4}' -f $removed, (Format-Size $freed), $skipped, (Format-Size $after.TotalBytes), $after.FileCount

    if ($after.TotalBytes -ge $totalLimit) {
        Exit-Script 1 "Partial | $result; Action=retry next run"
    }
    Exit-Script 0 "Fixed | $result"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
