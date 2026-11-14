<#
.SYNOPSIS
  Remediation script for pending Hybrid Entra join.

.DESCRIPTION
  Triggers the Automatic-Device-Join task and writes cases that need an administrator to the output.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowLeaveOnAuthFailure = $false

$PackageName = 'HybridJoinState'
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

try {
    $d = @{}
    foreach ($line in (& dsregcmd.exe /status)) { if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$') { $d[$Matches[1]] = $Matches[2] } }

    $taskPath = '\Microsoft\Windows\Workplace Join\'
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName 'Automatic-Device-Join' -ErrorAction SilentlyContinue
    $done = @()

    if ($d['AzureAdJoined'] -eq 'YES' -and $d['DeviceAuthStatus'] -and $d['DeviceAuthStatus'] -ne 'SUCCESS') {
        if (-not $AllowLeaveOnAuthFailure) { Exit-Script 1 "DeviceAuthStatus=$($d['DeviceAuthStatus']). Check device object in Entra (deleted/disabled). Auto leave is off." }
        & dsregcmd.exe /leave | Out-Null
        $done += 'dsregcmd /leave executed'
    }

    if ($d['DomainJoined'] -eq 'YES' -and ($d['AzureAdJoined'] -ne 'YES' -or $done)) {
        if (-not $task) { Exit-Script 1 'Automatic-Device-Join task missing.' }
        if ($task.State -eq 'Disabled') { Enable-ScheduledTask -InputObject $task | Out-Null; $done += 'Automatic-Device-Join enabled' }
        Start-ScheduledTask -InputObject $task -ErrorAction Stop
        $done += 'Automatic-Device-Join started'
    }

    if ($d['AzureAdJoined'] -eq 'YES' -and $d['WorkplaceJoined'] -eq 'YES') {
        $done += 'DualState reported only: deploy BlockAADWorkplaceJoin policy to clean it up'
    }

    if (-not $done) { $done = @('Nothing actionable') }
    Exit-Script 0 ($done -join '; ')
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
