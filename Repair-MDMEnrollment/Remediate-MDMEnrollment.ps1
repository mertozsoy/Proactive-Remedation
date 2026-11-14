<#
.SYNOPSIS
  Remediation script for a hybrid Entra joined device that is not enrolled in Intune.

.DESCRIPTION
  Finds the auto-enrollment task created by Group Policy, enables it when needed and starts it. Waits for the Intune enrollment key within a bounded window and exits 0 only when the enrollment exists.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnrollmentsRoot          = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$IntuneProviderId         = 'MS DM Server'
$AutoEnrollTaskPath       = '\Microsoft\Windows\EnterpriseMgmt\'
$AutoEnrollTaskNameMatch  = '*automatically enrolling in MDM*'
$EnrollmentWaitSeconds    = 90
$EnrollmentPollSeconds    = 10

$PackageName = 'MDMEnrollment'
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

function Get-DsregState {
    $state = @{}
    foreach ($line in (& dsregcmd.exe /status)) {
        if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$') { $state[$Matches[1]] = $Matches[2] }
    }
    $state
}

function Get-ActiveIntuneEnrollment {
    @(Get-ChildItem -LiteralPath $EnrollmentsRoot -ErrorAction SilentlyContinue | Where-Object {
        $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $item.ProviderID -eq $IntuneProviderId -and $item.EnrollmentState -eq 1
    })
}

function Get-AutoEnrollTask {
    @(Get-ScheduledTask -TaskPath $AutoEnrollTaskPath -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -like $AutoEnrollTaskNameMatch
    })
}

try {
    $dsreg = Get-DsregState
    if ($dsreg['DomainJoined'] -ne 'YES' -or $dsreg['AzureAdJoined'] -ne 'YES') {
        Exit-Script 0 "NotApplicable | DomainJoined=$($dsreg['DomainJoined']); AzureAdJoined=$($dsreg['AzureAdJoined'])"
    }

    $before = @(Get-ActiveIntuneEnrollment)
    if ($before.Count -gt 0) { Exit-Script 0 "Healthy | IntuneEnrollment=$($before.Count); Action=None" }

    $tasks = @(Get-AutoEnrollTask)
    if ($tasks.Count -eq 0) {
        Exit-Script 1 "Failed | AutoEnrollTask=Missing; Path=$AutoEnrollTaskPath; GP=Enable automatic MDM enrollment not applied"
    }

    $enabled = 0
    $started = 0
    foreach ($task in $tasks) {
        if ($task.State -eq 'Disabled') {
            Enable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop | Out-Null
            $enabled++
            Write-IRTLog "Enabled task $($task.TaskPath)$($task.TaskName)"
        }
        $current = Get-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop
        if ($current.State -ne 'Running') {
            Start-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop
        }
        $started++
        Write-IRTLog "Started task $($task.TaskPath)$($task.TaskName)"
    }

    $startTime = Get-Date
    $deadline  = $startTime.AddSeconds($EnrollmentWaitSeconds)
    $after     = @()
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $EnrollmentPollSeconds
        $after = @(Get-ActiveIntuneEnrollment)
        if ($after.Count -gt 0) { break }
    }
    $waited = [int]((Get-Date) - $startTime).TotalSeconds

    $summary = 'IntuneEnrollment={0}; AutoEnrollTask=Started; Started={1}; Enabled={2}; Waited={3}s' -f $after.Count, $started, $enabled, $waited
    if ($after.Count -gt 0) { Exit-Script 0 "Fixed | $summary" }
    Exit-Script 1 "Failed | $summary; Check event 76 in DeviceManagement-Enterprise-Diagnostic-Provider"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
