<#
.SYNOPSIS
  Remediation script that triggers TPM health attestation certificate retrieval.

.DESCRIPTION
  Starts the TPM health attestation retrieval task when the TPM is ready and the cached certificate is missing or stale. Waits for the task and checks the certificate status again. Exits 0 if a valid certificate is cached, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$HealthCertKey     = 'HKLM:\SYSTEM\CurrentControlSet\Services\TPM\WMI\HealthCert\Store\has.spserv.microsoft.com'
$HealthyStatus     = 3
$TaskPath          = '\Microsoft\Windows\TPM'
$TaskNameMatch     = '*HASCertRetr*'
$EnableRemediation = $true
$WaitSeconds       = 150

$PackageName = 'TpmHealthAttestation'
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
function Get-TpmState {
    try {
        $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
    } catch { return $null }
    if (-not $tpm) { return $null }
    $major = 0
    if ($tpm.SpecVersion) { $major = [int](($tpm.SpecVersion -split ',')[0] -split '\.')[0] }
    $ready = $false
    if ($tpm.IsEnabled_InitialValue -eq $true -and $tpm.IsActivated_InitialValue -eq $true) { $ready = $true }
    [pscustomobject]@{ Present = $true; Major = $major; Ready = $ready }
}
function Get-HealthCertStatus {
    if (-not (Test-Path -LiteralPath $HealthCertKey)) { return $null }
    try {
        $value = Get-ItemProperty -LiteralPath $HealthCertKey -Name 'Status' -ErrorAction Stop
    } catch { return $null }
    return [int]$value.Status
}
function Get-RetrievalTask {
    Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $TaskNameMatch } | Select-Object -First 1
}
function Format-TaskResult { param($Task)
    if (-not $Task) { return 'none' }
    try { $info = Get-ScheduledTaskInfo -InputObject $Task -ErrorAction Stop } catch { return 'unknown' }
    if ($null -eq $info.LastTaskResult) { return 'unknown' }
    return ('0x{0:X8}' -f $info.LastTaskResult)
}

try {
    $tpm = Get-TpmState
    if (-not $tpm) { Exit-Script 0 'NotApplicable | TpmPresent=False' }
    if ($tpm.Major -lt 2) { Exit-Script 0 "NotApplicable | TpmPresent=True; TpmVersion=$($tpm.Major)" }
    if (-not $tpm.Ready) { Exit-Script 0 'NotApplicable | TpmPresent=True; TpmReady=False' }

    $status = Get-HealthCertStatus
    if ($null -ne $status -and $status -eq $HealthyStatus) {
        Exit-Script 0 "Healthy | TpmReady=True; HealthCertStatus=$status"
    }

    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | TpmReady=True; HealthCertStatus=$status; EnableRemediation=False"
    }

    $task = Get-RetrievalTask
    if (-not $task) { Exit-Script 1 'Failed | RetrievalTask=Missing' }
    if ($task.State -eq 'Disabled') { Exit-Script 1 'Failed | RetrievalTask=Disabled' }
    Write-IRTLog "Starting task $($task.TaskPath)$($task.TaskName)"

    $started = Get-Date
    if ($task.State -ne 'Running') {
        Start-ScheduledTask -InputObject $task -ErrorAction Stop
    }

    Start-Sleep -Seconds 5
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $task = Get-RetrievalTask
        if (-not $task) { break }
        $info = $null
        try { $info = Get-ScheduledTaskInfo -InputObject $task -ErrorAction Stop } catch { }
        $ran = $false
        if ($info -and $info.LastRunTime -and $info.LastRunTime -ge $started.AddSeconds(-2)) { $ran = $true }
        if ($task.State -ne 'Running' -and $ran) { break }
        Start-Sleep -Seconds 5
    }

    $statusDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $statusDeadline) {
        $status = Get-HealthCertStatus
        if ($null -ne $status -and $status -eq $HealthyStatus) { break }
        Start-Sleep -Seconds 3
    }

    $task = Get-RetrievalTask
    $taskResult = Format-TaskResult -Task $task
    $taskState = 'Missing'
    if ($task) { $taskState = [string]$task.State }
    $status = Get-HealthCertStatus

    if ($null -ne $status -and $status -eq $HealthyStatus) {
        Exit-Script 0 "Fixed | TpmReady=True; HealthCertStatus=$status; TaskState=$taskState; TaskResult=$taskResult"
    }
    $shown = 'None'
    if ($null -ne $status) { $shown = [string]$status }
    Exit-Script 1 "Failed | TpmReady=True; HealthCertStatus=$shown; TaskState=$taskState; TaskResult=$taskResult"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
