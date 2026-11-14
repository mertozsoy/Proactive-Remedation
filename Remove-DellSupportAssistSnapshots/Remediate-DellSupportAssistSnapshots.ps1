<#
.SYNOPSIS
  Remediation script for Dell SupportAssist recovery snapshots that fill the system drive.

.DESCRIPTION
  Deletes the content of the SupportAssist system repair snapshot folder when $Enforce is true, otherwise only reports. Exits 0 when the folder is under $MaxSizeGB, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SnapshotPath = Join-Path $env:ProgramData 'Dell\SARemediation\SystemRepair\Snapshots'
$MaxSizeGB    = 5
$Enforce      = $false

$PackageName = 'DellSupportAssistSnapshots'
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
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [math]::Round(([double]$sum / 1GB), 1)
}

function Get-FreeGB {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    [math]::Round(($disk.FreeSpace / 1GB), 1)
}

try {
    if (-not (Test-Path -LiteralPath $SnapshotPath)) { Exit-Script 0 'NoAction | SnapshotFolder=NotFound' }

    $beforeGB   = Get-FolderSizeGB -Path $SnapshotPath
    $freeBefore = Get-FreeGB
    if ($beforeGB -le $MaxSizeGB) { Exit-Script 0 "NoAction | SnapshotGB=$beforeGB; LimitGB=$MaxSizeGB" }
    if (-not $Enforce) { Exit-Script 1 "ReportOnly | SnapshotGB=$beforeGB; FreeGB=$freeBefore; Enforce=False" }

    $failed = 0
    foreach ($item in Get-ChildItem -LiteralPath $SnapshotPath -Force -ErrorAction SilentlyContinue) {
        try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop; Write-IRTLog "Removed: $($item.Name)" }
        catch { $failed++; Write-IRTLog "Could not remove $($item.Name): $($_.Exception.Message)" 'WARN' }
    }

    $afterGB = Get-FolderSizeGB -Path $SnapshotPath
    $summary = 'BeforeGB={0}; AfterGB={1}; FreeBeforeGB={2}; FreeAfterGB={3}; FailedItems={4}' -f $beforeGB, $afterGB, $freeBefore, (Get-FreeGB), $failed
    if ($afterGB -gt $MaxSizeGB) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Cleaned | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
