<#
.SYNOPSIS
  Detection script for an oversized Delivery Optimization cache.

.DESCRIPTION
  Measures the Delivery Optimization cache folder and free space on the system drive. Exits 1 if the cache is over the size limit or takes too much of a nearly full disk.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxCacheGB         = 10
$LowFreePercent     = 15
$MaxCachePercentLow = 5

$PackageName = 'DeliveryOptimizationCache'
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

function Get-FolderSizeGB { param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    return [math]::Round(([double]$sum / 1GB), 2)
}

try {
    $cachePath = Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
    $policy    = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -ErrorAction SilentlyContinue
    $cacheDrive = $policy.DOModifyCacheDrive

    if ($cacheDrive) { Exit-Script 0 "NotApplicable | CacheDriveMovedByPolicy=$cacheDrive" }
    if (-not (Test-Path -LiteralPath $cachePath)) { Exit-Script 0 'NotApplicable | CacheFolder=Missing' }

    $disk     = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $diskGB   = [math]::Round($disk.Size / 1GB, 1)
    $freePct  = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
    $cacheGB  = Get-FolderSizeGB -Path $cachePath
    $cachePct = [math]::Round(($cacheGB / $diskGB) * 100, 1)

    $issues = @()
    if ($cacheGB -gt $MaxCacheGB) { $issues += "Cache>$MaxCacheGB GB" }
    if ($freePct -lt $LowFreePercent -and $cachePct -gt $MaxCachePercentLow) { $issues += "LowDisk+Cache>$MaxCachePercentLow%" }

    $summary = 'CacheGB={0}; CachePct={1}; FreePct={2}; MaxCacheSizePolicy={3}; AbsMaxCachePolicy={4}' -f $cacheGB, $cachePct, $freePct, $(if ($null -ne $policy.DOMaxCacheSize) { $policy.DOMaxCacheSize } else { 'NotSet' }), $(if ($null -ne $policy.DOAbsoluteMaxCacheSize) { $policy.DOAbsoluteMaxCacheSize } else { 'NotSet' })
    if ($issues) { Exit-Script 1 "Oversized ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
