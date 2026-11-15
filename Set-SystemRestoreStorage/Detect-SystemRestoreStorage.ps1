<#
.SYNOPSIS
  Detection script for oversized System Restore shadow copy storage.

.DESCRIPTION
  Reads the shadow storage association of each protected volume and compares the maximum space with the volume size. Exits 1 when a limit is unbounded or above the allowed percentage, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetPercent     = 10
$MaxAllowedPercent = 20

$PackageName = 'SystemRestoreStorage'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}
function Get-ShadowStorageState {
    $items = @()
    foreach ($entry in @(Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop)) {
        $drive = $entry.Volume.DriveLetter
        $capacity = [double]$entry.Volume.Capacity
        if (-not $drive -or $capacity -le 0) { continue }
        $maxSpace = [double]$entry.MaxSpace
        $unbounded = ($maxSpace -le 0 -or $maxSpace -ge $capacity)
        $percent = $null
        if (-not $unbounded) { $percent = [math]::Round(($maxSpace / $capacity) * 100, 1) }
        $items += [pscustomobject]@{
            Drive     = $drive
            DiffDrive = $entry.DiffVolume.DriveLetter
            Unbounded = $unbounded
            Percent   = $percent
            UsedGB    = [math]::Round([double]$entry.UsedSpace / 1GB, 1)
        }
    }
    $items
}
function Get-StateText { param([object[]]$Items)
    ($Items | ForEach-Object {
        if ($_.Unbounded) { '{0} Unbounded' -f $_.Drive }
        else { '{0} {1}%' -f $_.Drive, $_.Percent }
    }) -join ', '
}

try {
    if ($MaxAllowedPercent -le 0 -or $MaxAllowedPercent -ge 100) { throw 'MaxAllowedPercent must be between 1 and 99.' }
    if ($TargetPercent -le 0 -or $TargetPercent -ge $MaxAllowedPercent) { throw 'TargetPercent must be lower than MaxAllowedPercent.' }

    $volumes = @(Get-ShadowStorageState)
    if ($volumes.Count -eq 0) { Exit-Script 0 'NotApplicable | ShadowStorage=None' }

    foreach ($volume in $volumes) {
        Write-IRTLog "Measured | Volume=$($volume.Drive); Unbounded=$($volume.Unbounded); Percent=$($volume.Percent); UsedGB=$($volume.UsedGB)"
    }

    $drift = @($volumes | Where-Object { $_.Unbounded -or $_.Percent -gt $MaxAllowedPercent })
    $state = Get-StateText -Items $volumes
    if ($drift.Count -gt 0) {
        Exit-Script 1 "Drift | Volumes=$state; Allowed=$MaxAllowedPercent%; Target=$TargetPercent%; Count=$($drift.Count)"
    }
    Exit-Script 0 "Healthy | Volumes=$state; Allowed=$MaxAllowedPercent%; Count=$($volumes.Count)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
