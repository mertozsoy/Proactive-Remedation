<#
.SYNOPSIS
  Remediation script for an oversized Delivery Optimization cache.

.DESCRIPTION
  Clears the Delivery Optimization cache with the built-in cmdlet and measures it again. Pinned files are kept. Exits 0 if the cache is back under the limit, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MaxCacheGB = 10

$PackageName = 'DeliveryOptimizationCache'
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

function Get-FolderSizeGB { param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    return [math]::Round(([double]$sum / 1GB), 2)
}

try {
    $cachePath = Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
    $before    = Get-FolderSizeGB -Path $cachePath

    $active = @(Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Downloading' })
    Write-IRTLog "Cache before: $before GB; active downloads: $($active.Count)"

    Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
    Start-Sleep -Seconds 5

    $after = Get-FolderSizeGB -Path $cachePath
    $freed = [math]::Round($before - $after, 2)
    $summary = "BeforeGB=$before; AfterGB=$after; FreedGB=$freed; ActiveDownloads=$($active.Count)"
    if ($after -le $MaxCacheGB) { Exit-Script 0 "Cleaned | $summary" }
    Exit-Script 1 "StillOversized (pinned or in-use files) | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
