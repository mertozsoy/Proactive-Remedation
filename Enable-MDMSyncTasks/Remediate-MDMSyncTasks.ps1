<#
.SYNOPSIS
  Remediation script for the Task Scheduler service and MDM sync tasks.

.DESCRIPTION
  Sets the Task Scheduler service to Automatic, enables the disabled EnterpriseMgmt tasks and starts PushLaunch. Missing tasks are only reported. Exits 0 when the service runs and no task is disabled.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TaskRoot = '\Microsoft\Windows\EnterpriseMgmt\'

$PackageName = 'MDMSyncTasks'
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

function Get-IntuneEnrollmentId {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -Name ProviderID -ErrorAction SilentlyContinue).ProviderID -eq 'MS DM Server'
    } | ForEach-Object { $_.PSChildName }
}

try {
    $schedKey   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Schedule'
    $rebootNeed = $false

    if ((Get-ItemProperty $schedKey -Name Start -ErrorAction SilentlyContinue).Start -ne 2) {
        $out = & sc.exe config Schedule start= auto 2>&1
        Write-IRTLog "sc.exe config Schedule exit $LASTEXITCODE : $($out -join ' ')"
        if ($LASTEXITCODE -ne 0) {
            Set-ItemProperty -Path $schedKey -Name Start -Value 2 -Type DWord -ErrorAction Stop
            $rebootNeed = $true
            Write-IRTLog 'Schedule Start set to 2 in the registry, takes effect after restart' 'WARN'
        }
    }

    if ((Get-Service -Name Schedule).Status -ne 'Running') {
        try { Start-Service -Name Schedule -ErrorAction Stop } catch { Write-IRTLog "Start-Service Schedule: $($_.Exception.Message)" 'WARN' }
    }
    $schedSvc = Get-Service -Name Schedule
    if ($schedSvc.Status -ne 'Running') {
        Exit-Script 1 "Failed | Schedule=$($schedSvc.Status); RebootRequired=$rebootNeed"
    }

    $enrollments = @(Get-IntuneEnrollmentId)
    if ($enrollments.Count -eq 0) { Exit-Script 1 'Failed | Enrollment=None; re-enrollment is a manual step' }

    $enabled = 0; $missing = New-Object System.Collections.Generic.List[string]
    foreach ($id in $enrollments) {
        $path  = "$TaskRoot$id\"
        $tasks = @(Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue)
        if ($tasks.Count -eq 0) { $missing.Add($id); continue }
        foreach ($t in ($tasks | Where-Object { $_.State -eq 'Disabled' })) {
            Enable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
            Write-IRTLog "Enabled task: $path$($t.TaskName)"
            $enabled++
        }
        $push = Get-ScheduledTask -TaskPath $path -TaskName 'PushLaunch' -ErrorAction SilentlyContinue
        if ($push) { Start-ScheduledTask -InputObject $push -ErrorAction Stop; Write-IRTLog "Started PushLaunch for $id" }
        else { $missing.Add("$id/PushLaunch") }
    }

    $stillDisabled = 0
    foreach ($id in $enrollments) {
        $stillDisabled += @(Get-ScheduledTask -TaskPath "$TaskRoot$id\" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Disabled' }).Count
    }

    $summary = 'Enabled={0}; StillDisabled={1}; Schedule={2}; RebootRequired={3}' -f $enabled, $stillDisabled, $schedSvc.Status, $rebootNeed
    if ($missing.Count -gt 0) { Exit-Script 1 "Failed (TasksMissing=$($missing -join ',')) | $summary" }
    if ($stillDisabled -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Remediated | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
