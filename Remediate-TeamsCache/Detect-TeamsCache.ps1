<#
.SYNOPSIS
  Detection script for the new Microsoft Teams cache.

.DESCRIPTION
  Measures the new Teams cache of the signed-in user and checks whether Teams is running. Exits 1 if the cache is at or above the size threshold, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinimumCacheMB    = 300
$TeamsCachePath    = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
$TeamsProcessName  = 'ms-teams'

$PackageName = 'TeamsCache'
$Phase       = 'Detect'
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

try {
    if ($MinimumCacheMB -lt 1) { Exit-Script 1 'Failed | Reason=InvalidThreshold' }
    if (-not (Test-Path -LiteralPath $TeamsCachePath -PathType Container)) {
        Exit-Script 0 'NotApplicable | NewTeamsCache=Missing'
    }

    $state   = Get-TeamsCacheState
    $summary = 'CacheMB={0}; ThresholdMB={1}; Files={2}; TeamsRunning={3}' -f $state.MB, $MinimumCacheMB, $state.Files, $state.Running
    if ($state.MB -ge $MinimumCacheMB) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
