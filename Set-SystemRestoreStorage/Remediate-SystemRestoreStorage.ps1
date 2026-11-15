<#
.SYNOPSIS
  Remediation script that caps System Restore shadow copy storage.

.DESCRIPTION
  Lowers the maximum shadow copy storage of protected volumes to the target percentage with vssadmin and reads the values back. Exits 0 when every volume is within the limit, 1 when a volume still exceeds it or a resize fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TargetPercent     = 10
$MaxAllowedPercent = 20

$PackageName = 'SystemRestoreStorage'
$Phase       = 'Remediate'
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

    $changed = 0
    $failed = 0
    $vssadmin = Join-Path $env:SystemRoot 'System32\vssadmin.exe'
    foreach ($volume in $volumes) {
        if (-not $volume.Unbounded -and $volume.Percent -le $MaxAllowedPercent) {
            Write-IRTLog "Healthy | Volume=$($volume.Drive); Percent=$($volume.Percent)"
            continue
        }
        $onDrive = $volume.DiffDrive
        if (-not $onDrive) { $onDrive = $volume.Drive }
        Write-IRTLog "Resizing | Volume=$($volume.Drive); On=$onDrive; Unbounded=$($volume.Unbounded); Percent=$($volume.Percent)"
        $arguments = @('resize', 'shadowstorage', "/for=$($volume.Drive)", "/on=$onDrive", "/maxsize=$TargetPercent%")
        $process = Start-Process -FilePath $vssadmin -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            $failed++
            Write-IRTLog "ResizeFailed | Volume=$($volume.Drive); ExitCode=$($process.ExitCode)" 'ERROR'
            continue
        }
        $changed++
    }

    $after = @(Get-ShadowStorageState)
    $remaining = @($after | Where-Object { $_.Unbounded -or $_.Percent -gt ($TargetPercent + 2) })
    $state = Get-StateText -Items $after
    $summary = "Volumes=$state; Changed=$changed; Failed=$failed"
    if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | $summary; Remaining=$($remaining.Count)" }
    if ($failed -gt 0) { Exit-Script 1 "Failed | $summary" }
    if ($changed -eq 0) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
