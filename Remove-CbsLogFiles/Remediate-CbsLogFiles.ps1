<#
.SYNOPSIS
  Remediation script that deletes old CBS archive logs when the folder fills the system disk.

.DESCRIPTION
  Removes CbsPersist files older than the age limit and keeps the newest archives. Trims the active CBS.log only when the Windows Modules Installer service is stopped. Exits 0 if the folder is back under the limit, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$FolderSizeLimitMB  = 1024
$ArchiveSizeLimitMB = 512
$MaxArchiveFiles    = 20
$ActiveLogLimitMB   = 1024
$MinFileAgeDays     = 7
$KeepNewestArchives = 2
$RemoveArchiveFiles = $true
$TrimActiveLog      = $true

$PackageName = 'CbsLogFiles'
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

    $archives    = @($files | Where-Object { $_.Name -like 'CbsPersist_*' })
    $active      = @($files | Where-Object { $_.Name -eq 'CBS.log' })
    $totalBytes  = [double](($files | Measure-Object -Property Length -Sum).Sum)
    $archiveSize = [double](($archives | Measure-Object -Property Length -Sum).Sum)
    $activeSize  = 0
    if ($active.Count -gt 0) { $activeSize = [double]$active[0].Length }

    $overFolder  = $totalBytes -ge ($FolderSizeLimitMB * 1MB)
    $overArchive = ($archiveSize -ge ($ArchiveSizeLimitMB * 1MB)) -or ($archives.Count -gt $MaxArchiveFiles)

    if (-not ($overFolder -or $overArchive)) {
        $healthy = 'Healthy | Folder={0}; Archive={1}; ArchiveFiles={2}; Active={3}' -f (Format-Size $totalBytes), (Format-Size $archiveSize), $archives.Count, (Format-Size $activeSize)
        Exit-Script 0 $healthy
    }

    Write-IRTLog ('Over limit: folder {0} archives {1} count {2}' -f (Format-Size $totalBytes), (Format-Size $archiveSize), $archives.Count)

    if (-not $RemoveArchiveFiles) {
        $report = 'Drift | Folder={0}; Archive={1}; ArchiveFiles={2}; Action=report only' -f (Format-Size $totalBytes), (Format-Size $archiveSize), $archives.Count
        Exit-Script 1 $report
    }

    $keep = @()
    if ($archives.Count -gt 0) {
        $keep = @($archives | Sort-Object LastWriteTime -Descending | Select-Object -First $KeepNewestArchives | ForEach-Object { $_.FullName })
    }

    $cutoff  = (Get-Date).AddDays(-1 * $MinFileAgeDays)
    $removed = 0
    $freed   = 0
    $skipped = 0

    foreach ($file in ($archives | Sort-Object LastWriteTime)) {
        if ($file.LastWriteTime -ge $cutoff) { continue }
        if ($keep -contains $file.FullName) { continue }
        $size = [double]$file.Length
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++
            $freed += $size
            Write-IRTLog ('Removed {0} ({1})' -f $file.FullName, (Format-Size $size))
        }
        catch {
            $skipped++
            Write-IRTLog -Message ('Skip {0}: {1}' -f $file.FullName, $_.Exception.Message) -Level 'WARN'
        }
    }

    $trimState  = 'NotNeeded'
    $files      = @(Get-ChildItem -LiteralPath $CbsLogRoot -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
    $totalBytes = [double](($files | Measure-Object -Property Length -Sum).Sum)

    if ($totalBytes -ge ($FolderSizeLimitMB * 1MB)) {
        if (-not $TrimActiveLog) {
            $trimState = 'Disabled'
        }
        else {
            $active = @($files | Where-Object { $_.Name -eq 'CBS.log' })
            if ($active.Count -eq 0) {
                $trimState = 'NoActiveLog'
            }
            elseif ($active[0].Length -lt ($ActiveLogLimitMB * 1MB)) {
                $trimState = 'NotNeeded'
            }
            else {
                $service = Get-Service -Name 'TrustedInstaller' -ErrorAction SilentlyContinue
                if ($null -eq $service) {
                    $trimState = 'MissingService'
                }
                elseif ($service.Status -ne 'Stopped') {
                    $trimState = 'ServiceRunning'
                }
                else {
                    $size = [double]$active[0].Length
                    try {
                        Remove-Item -LiteralPath $active[0].FullName -Force -ErrorAction Stop
                        $removed++
                        $freed += $size
                        $trimState = 'Yes'
                        Write-IRTLog ('Removed active CBS.log ({0})' -f (Format-Size $size))
                    }
                    catch {
                        $skipped++
                        $trimState = 'Failed'
                        Write-IRTLog -Message ('Skip CBS.log: {0}' -f $_.Exception.Message) -Level 'WARN'
                    }
                }
            }
        }
    }

    $files        = @(Get-ChildItem -LiteralPath $CbsLogRoot -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
    $archives     = @($files | Where-Object { $_.Name -like 'CbsPersist_*' })
    $active       = @($files | Where-Object { $_.Name -eq 'CBS.log' })
    $finalBytes   = [double](($files | Measure-Object -Property Length -Sum).Sum)
    $finalArchive = [double](($archives | Measure-Object -Property Length -Sum).Sum)
    $finalActive  = 0
    if ($active.Count -gt 0) { $finalActive = [double]$active[0].Length }

    $result = 'Removed={0}; Freed={1}; Folder={2}; Archive={3}; Active={4}; Trimmed={5}; Skipped={6}' -f $removed, (Format-Size $freed), (Format-Size $finalBytes), (Format-Size $finalArchive), (Format-Size $finalActive), $trimState, $skipped

    $stillOver = ($finalBytes -ge ($FolderSizeLimitMB * 1MB)) -or ($finalArchive -ge ($ArchiveSizeLimitMB * 1MB)) -or ($archives.Count -gt $MaxArchiveFiles)
    if ($stillOver) { Exit-Script 1 "Partial | $result; Action=retry next run" }
    Exit-Script 0 "Fixed | $result"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
