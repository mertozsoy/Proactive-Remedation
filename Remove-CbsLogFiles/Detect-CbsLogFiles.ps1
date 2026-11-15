<#
.SYNOPSIS
  Detection script for a CBS log folder that grows until the system disk is full.

.DESCRIPTION
  Measures C:\Windows\Logs\CBS, the CbsPersist archive files and the active CBS.log. Exits 1 if the folder total, the archive size or the archive count is over the limit, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$FolderSizeLimitMB  = 1024
$ArchiveSizeLimitMB = 512
$MaxArchiveFiles    = 20
$ActiveLogLimitMB   = 1024

$PackageName = 'CbsLogFiles'
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

$CbsLogRoot = Join-Path $env:windir 'Logs\CBS'

function Format-Size { param([double]$Bytes)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1GB) { return ([string]::Format($inv, '{0:N1}GB', ($Bytes / 1GB))) }
    if ($Bytes -ge 1MB) { return ([string]::Format($inv, '{0:N0}MB', ($Bytes / 1MB))) }
    if ($Bytes -ge 1KB) { return ([string]::Format($inv, '{0:N0}KB', ($Bytes / 1KB))) }
    return ([string]::Format($inv, '{0}B', $Bytes))
}

try {
    if (-not (Test-Path -LiteralPath $CbsLogRoot)) { Exit-Script 0 'NotApplicable | CBS log folder not found' }

    $files = @(Get-ChildItem -LiteralPath $CbsLogRoot -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
    if ($files.Count -eq 0) { Exit-Script 0 'Healthy | Folder=0B; Files=0; Archive=0B; ArchiveFiles=0; Active=0B' }

    $archives = @($files | Where-Object { $_.Name -like 'CbsPersist_*' })
    $active   = @($files | Where-Object { $_.Name -eq 'CBS.log' })

    $totalBytes   = [double](($files | Measure-Object -Property Length -Sum).Sum)
    $archiveBytes = [double](($archives | Measure-Object -Property Length -Sum).Sum)
    $activeBytes  = 0
    if ($active.Count -gt 0) { $activeBytes = [double]$active[0].Length }

    $summary = 'Folder={0}; Files={1}; Archive={2}; ArchiveFiles={3}; Active={4}' -f (Format-Size $totalBytes), $files.Count, (Format-Size $archiveBytes), $archives.Count, (Format-Size $activeBytes)
    if ($archives.Count -gt 0) {
        $largest = ($archives | Sort-Object Length -Descending | Select-Object -First 1).Name
        $summary = $summary + '; Largest=' + $largest
    }
    Write-IRTLog $summary

    if ($totalBytes -ge ($FolderSizeLimitMB * 1MB)) { Exit-Script 1 "Drift | $summary; Reason=folder over $($FolderSizeLimitMB)MB" }
    if ($archiveBytes -ge ($ArchiveSizeLimitMB * 1MB)) { Exit-Script 1 "Drift | $summary; Reason=archives over $($ArchiveSizeLimitMB)MB" }
    if ($archives.Count -gt $MaxArchiveFiles) { Exit-Script 1 "Drift | $summary; Reason=more than $MaxArchiveFiles archive files" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
