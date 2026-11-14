<#
.SYNOPSIS
  Detection script for Dell SupportAssist recovery snapshots that fill the system drive.

.DESCRIPTION
  Measures the SupportAssist system repair snapshot folder. Exits 1 if it is larger than $MaxSizeGB, 0 if it is smaller or the folder does not exist.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SnapshotPath = Join-Path $env:ProgramData 'Dell\SARemediation\SystemRepair\Snapshots'
$MaxSizeGB    = 5
$Enforce      = $false

$PackageName = 'DellSupportAssistSnapshots'
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
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [math]::Round(([double]$sum / 1GB), 1)
}

function Get-FreeGB {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    [math]::Round(($disk.FreeSpace / 1GB), 1)
}

try {
    if (-not (Test-Path -LiteralPath $SnapshotPath)) { Exit-Script 0 'NotApplicable | SnapshotFolder=NotFound' }

    $sizeGB  = Get-FolderSizeGB -Path $SnapshotPath
    $count   = @(Get-ChildItem -LiteralPath $SnapshotPath -Force -ErrorAction SilentlyContinue).Count
    $summary = 'SnapshotGB={0}; Items={1}; FreeGB={2}; LimitGB={3}' -f $sizeGB, $count, (Get-FreeGB), $MaxSizeGB

    if ($sizeGB -gt $MaxSizeGB) { Exit-Script 1 "OverLimit | $summary" }
    Exit-Script 0 "OK | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
