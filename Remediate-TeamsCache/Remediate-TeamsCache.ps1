<#
.SYNOPSIS
  Remediation script for the new Microsoft Teams cache.

.DESCRIPTION
  Clears the new Teams cache of the signed-in user when it reaches the size threshold. Teams is closed first and the script checks that the cache stays below the threshold. Exits 0 after a verified cleanup, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinimumCacheMB   = 300
$StopTeamsProcess = $false
$KeepLogs         = $true
$TeamsCachePath   = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
$TeamsProcessName = 'ms-teams'

$PackageName = 'TeamsCache'
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

function Get-CacheFile {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
    if ($item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop) {
            Get-CacheFile -Path $child.FullName
        }
        return
    }
    $item
}

function Get-TeamsCacheState {
    $files = @(Get-CacheFile -Path $TeamsCachePath)
    [int64]$bytes = 0
    foreach ($file in $files) { $bytes += $file.Length }
    [pscustomobject]@{
        Files   = $files.Count
        MB      = [math]::Round($bytes / 1MB)
        Running = (@(Get-Process -Name $TeamsProcessName -ErrorAction SilentlyContinue).Count -gt 0)
    }
}

function Close-TeamsClient {
    foreach ($process in @(Get-Process -Name $TeamsProcessName -ErrorAction SilentlyContinue)) {
        try { [void]$process.CloseMainWindow() } catch { Write-IRTLog "CloseMainWindow $($process.Id): $($_.Exception.Message)" 'WARN' }
    }
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-Process -Name $TeamsProcessName -ErrorAction SilentlyContinue).Count -eq 0) { return $true }
        Start-Sleep -Seconds 2
    }
    foreach ($process in @(Get-Process -Name $TeamsProcessName -ErrorAction SilentlyContinue)) {
        try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch { Write-IRTLog "StopProcess $($process.Id): $($_.Exception.Message)" 'WARN' }
    }
    Start-Sleep -Seconds 3
    return (@(Get-Process -Name $TeamsProcessName -ErrorAction SilentlyContinue).Count -eq 0)
}

try {
    if ($MinimumCacheMB -lt 1) { Exit-Script 1 'Failed | Reason=InvalidThreshold' }
    if (-not (Test-Path -LiteralPath $TeamsCachePath -PathType Container)) {
        Exit-Script 0 'NotApplicable | NewTeamsCache=Missing'
    }

    $before = Get-TeamsCacheState
    if ($before.MB -lt $MinimumCacheMB) {
        Exit-Script 0 ('Healthy | CacheMB={0}; ThresholdMB={1}; Files={2}' -f $before.MB, $MinimumCacheMB, $before.Files)
    }

    if ($before.Running) {
        if (-not $StopTeamsProcess) {
            Exit-Script 1 ('ReportOnly | Reason=TeamsRunning; CacheMB={0}; ThresholdMB={1}' -f $before.MB, $MinimumCacheMB)
        }
        if (-not (Close-TeamsClient)) { Exit-Script 1 'Failed | Reason=TeamsStillRunning' }
    }

    $deleted = 0
    $failed  = 0
    [int64]$removedBytes = 0
    foreach ($child in @(Get-ChildItem -LiteralPath $TeamsCachePath -Force -ErrorAction Stop)) {
        if ($KeepLogs -and $child.PSIsContainer -and $child.Name -eq 'logs') { continue }
        foreach ($file in @(Get-CacheFile -Path $child.FullName)) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $deleted++
                $removedBytes += $file.Length
            }
            catch {
                $failed++
                Write-IRTLog "Remove $($file.FullName): $($_.Exception.Message)" 'WARN'
            }
        }
    }

    $after   = Get-TeamsCacheState
    $summary = 'CacheMB={0}; ThresholdMB={1}; DeletedFiles={2}; RemovedMB={3}; FailedFiles={4}; TeamsRunning={5}' -f $after.MB, $MinimumCacheMB, $deleted, [math]::Round($removedBytes / 1MB), $failed, $after.Running
    if ($after.MB -lt $MinimumCacheMB) { Exit-Script 0 "Fixed | $summary" }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
