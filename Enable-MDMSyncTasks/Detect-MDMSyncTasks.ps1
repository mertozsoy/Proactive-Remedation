<#
.SYNOPSIS
  Detection script for the Task Scheduler service and MDM sync tasks.

.DESCRIPTION
  Checks the Task Scheduler service and the EnterpriseMgmt tasks of the Intune enrollment. Exits 1 if the service is disabled or stopped, or a sync task is disabled or missing.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TaskRoot = '\Microsoft\Windows\EnterpriseMgmt\'

$PackageName = 'MDMSyncTasks'
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

function Get-IntuneEnrollmentId {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -Name ProviderID -ErrorAction SilentlyContinue).ProviderID -eq 'MS DM Server'
    } | ForEach-Object { $_.PSChildName }
}

try {
    $issues = New-Object System.Collections.Generic.List[string]

    $schedStart = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Schedule' -Name Start -ErrorAction SilentlyContinue).Start
    $schedSvc   = Get-Service -Name Schedule -ErrorAction SilentlyContinue
    if ($schedStart -ne 2)                  { $issues.Add("Schedule.Start=$schedStart") }
    if ($schedSvc.Status -ne 'Running')     { $issues.Add("Schedule=$($schedSvc.Status)") }

    $enrollments = @(Get-IntuneEnrollmentId)
    if ($enrollments.Count -eq 0) {
        Exit-Script 0 "NotApplicable | Enrollment=None; ScheduleStart=$schedStart; Schedule=$($schedSvc.Status)"
    }

    $disabledTotal = 0; $taskTotal = 0
    if ($schedSvc.Status -eq 'Running') {
        foreach ($id in $enrollments) {
            $tasks = @(Get-ScheduledTask -TaskPath "$TaskRoot$id\" -ErrorAction SilentlyContinue)
            $taskTotal += $tasks.Count
            if ($tasks.Count -eq 0) { $issues.Add("Tasks=Missing($id)"); continue }
            if (-not ($tasks | Where-Object { $_.TaskName -eq 'PushLaunch' })) { $issues.Add("PushLaunch=Missing($id)") }
            $disabled = @($tasks | Where-Object { $_.State -eq 'Disabled' })
            $disabledTotal += $disabled.Count
            foreach ($t in $disabled) { Write-IRTLog "Disabled task: $($t.TaskPath)$($t.TaskName)" 'WARN' }
        }
        if ($disabledTotal -gt 0) { $issues.Add("DisabledTasks=$disabledTotal") }
    }

    $summary = 'Enrollment={0}; ScheduleStart={1}; Schedule={2}; Tasks={3}; Disabled={4}' -f ($enrollments -join ','), $schedStart, $schedSvc.Status, $taskTotal, $disabledTotal
    if ($issues.Count -gt 0) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
