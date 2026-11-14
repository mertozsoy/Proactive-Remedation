<#
.SYNOPSIS
  Remediation script that deletes oversized WinGet COM log files from the Windows temp folder.

.DESCRIPTION
  Removes WinGet log files that are older than the age limit when the folder or a single file is over the size limit. Exits 0 if the folder is back under the limit, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$FolderSizeLimitMB = 2048
$SingleFileLimitMB = 512
$MinFileAgeMinutes = 15
$RemoveLogFiles    = $true

$PackageName = 'WinGetComLogs'
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

$WinGetRoot = Join-Path $env:windir 'Temp\WinGet'

function Format-Size { param([double]$Bytes)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1GB) { return ([string]::Format($inv, '{0:N1}GB', ($Bytes / 1GB))) }
    if ($Bytes -ge 1MB) { return ([string]::Format($inv, '{0:N0}MB', ($Bytes / 1MB))) }
    if ($Bytes -ge 1KB) { return ([string]::Format($inv, '{0:N0}KB', ($Bytes / 1KB))) }
    return ([string]::Format($inv, '{0}B', $Bytes))
}

function Get-WinGetLogFile {
    if (-not (Test-Path -LiteralPath $WinGetRoot)) { return @() }
    @(Get-ChildItem -LiteralPath $WinGetRoot -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer -and ($_.Extension -eq '.txt' -or $_.Extension -eq '.log') })
}

try {
    if (-not (Test-Path -LiteralPath $WinGetRoot)) { Exit-Script 0 'NotApplicable | WinGet temp folder not found' }

    $files = @(Get-WinGetLogFile)
    if ($files.Count -eq 0) { Exit-Script 0 'Healthy | Folder=0MB; Files=0' }

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    $largest    = ($files | Sort-Object Length -Descending | Select-Object -First 1)
    $folderLimitBytes = $FolderSizeLimitMB * 1MB
    $fileLimitBytes   = $SingleFileLimitMB * 1MB

    $overLimit = ($totalBytes -ge $folderLimitBytes) -or ($largest.Length -ge $fileLimitBytes)
    if (-not $overLimit) {
        $healthy = 'Healthy | Folder={0}; Files={1}; Largest={2}' -f (Format-Size $totalBytes), $files.Count, (Format-Size $largest.Length)
        Exit-Script 0 $healthy
    }

    $sizeText = Format-Size $totalBytes
    $largestText = Format-Size $largest.Length
    Write-IRTLog ('Over limit: folder {0} files {1} largest {2} ({3})' -f $sizeText, $files.Count, $largestText, $largest.Name)

    if (-not $RemoveLogFiles) {
        $report = 'Drift | Folder={0}; Files={1}; Largest={2}; Action=report only' -f $sizeText, $files.Count, $largestText
        Exit-Script 1 $report
    }

    $cutoff  = (Get-Date).AddMinutes(-1 * $MinFileAgeMinutes)
    $removed = 0
    $freed   = 0
    $locked  = 0
    foreach ($file in ($files | Sort-Object LastWriteTime)) {
        if ($file.LastWriteTime -gt $cutoff) { continue }
        $size = $file.Length
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++
            $freed += $size
            Write-IRTLog ('Removed {0} ({1})' -f $file.FullName, (Format-Size $size))
        }
        catch {
            $locked++
            Write-IRTLog -Message ('Skip {0}: {1}' -f $file.FullName, $_.Exception.Message) -Level 'WARN'
        }
    }

    $remaining = @(Get-WinGetLogFile)
    $remainBytes = 0
    if ($remaining.Count -gt 0) { $remainBytes = ($remaining | Measure-Object -Property Length -Sum).Sum }
    $remainLargest = 0
    if ($remaining.Count -gt 0) { $remainLargest = ($remaining | Sort-Object Length -Descending | Select-Object -First 1).Length }

    $remainText = Format-Size $remainBytes
    $freedText = Format-Size $freed
    $result = 'Folder={0}; Files={1}; Removed={2}; Freed={3}; Skipped={4}' -f $remainText, $remaining.Count, $removed, $freedText, $locked
    if ($remainBytes -ge $folderLimitBytes -or $remainLargest -ge $fileLimitBytes) {
        Exit-Script 1 "Partial | $result; Action=retry next run"
    }
    Exit-Script 0 "Fixed | $result"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
