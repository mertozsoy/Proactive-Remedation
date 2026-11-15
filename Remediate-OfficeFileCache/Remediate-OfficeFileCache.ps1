<#
.SYNOPSIS
  Remediation script for the Office document cache.

.DESCRIPTION
  Clears the OfficeFileCache folder of the signed-in user when it reaches the size threshold. The cache is cleared only while no Office process is running and the result is verified. Exits 0 after a verified cleanup, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MinimumCacheMB        = 2048
$ClearCache            = $false
$SkipWhenOfficeRunning = $true
$CacheFolderName       = 'OfficeFileCache'
$OfficeProcessNames    = @('WINWORD', 'EXCEL', 'POWERPNT', 'MSOUC')

$PackageName = 'OfficeFileCache'
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

function Get-OfficeCachePath {
    $officeRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Office'
    if (-not (Test-Path -LiteralPath $officeRoot -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $officeRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+$' } |
        ForEach-Object { Join-Path $_.FullName $CacheFolderName } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container })
}

function Get-CacheState {
    param([string[]]$Paths)
    $files = 0
    [int64]$bytes = 0
    foreach ($path in $Paths) {
        foreach ($file in @(Get-CacheFile -Path $path)) {
            $files++
            $bytes += $file.Length
        }
    }
    [pscustomobject]@{
        Files = $files
        MB    = [math]::Round($bytes / 1MB)
    }
}

try {
    if ($MinimumCacheMB -lt 1) { Exit-Script 1 'Failed | Reason=InvalidThreshold' }

    $cachePaths = @(Get-OfficeCachePath)
    if ($cachePaths.Count -eq 0) { Exit-Script 0 'NotApplicable | OfficeFileCache=Missing' }

    $before = Get-CacheState -Paths $cachePaths
    if ($before.MB -lt $MinimumCacheMB) {
        Exit-Script 0 ('Healthy | CacheMB={0}; ThresholdMB={1}; Files={2}' -f $before.MB, $MinimumCacheMB, $before.Files)
    }

    $running = (@(Get-Process -Name $OfficeProcessNames -ErrorAction SilentlyContinue).Count -gt 0)
    if ($running -and $SkipWhenOfficeRunning) {
        Exit-Script 0 ('Deferred | Reason=OfficeRunning; CacheMB={0}; ThresholdMB={1}; Files={2}' -f $before.MB, $MinimumCacheMB, $before.Files)
    }
    if (-not $ClearCache) {
        Exit-Script 1 ('ReportOnly | Reason=ClearCacheDisabled; CacheMB={0}; ThresholdMB={1}; Files={2}' -f $before.MB, $MinimumCacheMB, $before.Files)
    }

    $deleted = 0
    $failed  = 0
    [int64]$removedBytes = 0
    foreach ($path in $cachePaths) {
        foreach ($child in @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)) {
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
    }

    $after   = Get-CacheState -Paths $cachePaths
    $summary = 'CacheMB={0}; ThresholdMB={1}; DeletedFiles={2}; RemovedMB={3}; FailedFiles={4}; FilesLeft={5}' -f $after.MB, $MinimumCacheMB, $deleted, [math]::Round($removedBytes / 1MB), $failed, $after.Files
    if ($after.MB -lt $MinimumCacheMB) { Exit-Script 0 "Fixed | $summary" }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
