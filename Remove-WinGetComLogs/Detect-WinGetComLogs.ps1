<#
.SYNOPSIS
  Detection script for WinGet COM log files that grow until the disk is full.

.DESCRIPTION
  Measures the WinGet folder under Windows\Temp and the largest log file in it. Exits 1 if the folder or a single file is over the limit, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$FolderSizeLimitMB = 2048
$SingleFileLimitMB = 512

$PackageName = 'WinGetComLogs'
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

$WinGetRoot = Join-Path $env:windir 'Temp\WinGet'

function Format-Size { param([double]$Bytes)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1GB) { return ([string]::Format($inv, '{0:N1}GB', ($Bytes / 1GB))) }
    if ($Bytes -ge 1MB) { return ([string]::Format($inv, '{0:N0}MB', ($Bytes / 1MB))) }
    if ($Bytes -ge 1KB) { return ([string]::Format($inv, '{0:N0}KB', ($Bytes / 1KB))) }
    return ([string]::Format($inv, '{0}B', $Bytes))
}

try {
    if (-not (Test-Path -LiteralPath $WinGetRoot)) { Exit-Script 0 'NotApplicable | WinGet temp folder not found' }

    $files = @(Get-ChildItem -LiteralPath $WinGetRoot -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer -and ($_.Extension -eq '.txt' -or $_.Extension -eq '.log') })
    if ($files.Count -eq 0) { Exit-Script 0 'Healthy | Folder=0MB; Files=0; Largest=0MB' }

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    $largest    = ($files | Sort-Object Length -Descending | Select-Object -First 1)

    $summary = 'Folder={0}; Files={1}; Largest={2}; LargestFile={3}' -f (Format-Size $totalBytes), $files.Count, (Format-Size $largest.Length), $largest.Name
    Write-IRTLog $summary

    $folderLimitBytes = $FolderSizeLimitMB * 1MB
    $fileLimitBytes   = $SingleFileLimitMB * 1MB

    if ($totalBytes -ge $folderLimitBytes) { Exit-Script 1 "Drift | $summary; Reason=folder over $($FolderSizeLimitMB)MB" }
    if ($largest.Length -ge $fileLimitBytes) { Exit-Script 1 "Drift | $summary; Reason=file over $($SingleFileLimitMB)MB" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
