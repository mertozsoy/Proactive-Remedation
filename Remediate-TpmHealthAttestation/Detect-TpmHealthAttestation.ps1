<#
.SYNOPSIS
  Detection script for the TPM health attestation certificate.

.DESCRIPTION
  Reads the TPM state and the cached health attestation certificate status from the TPM WMI store. Exits 1 if the TPM is ready but no valid certificate is cached, 0 if the cache is healthy or the device is out of scope.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$HealthCertKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\TPM\WMI\HealthCert\Store\has.spserv.microsoft.com'
$HealthyStatus = 3
$TaskPath      = '\Microsoft\Windows\TPM'
$TaskNameMatch = '*HASCertRetr*'

$PackageName = 'TpmHealthAttestation'
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

try {
    $tpm = Get-TpmState
    if (-not $tpm) { Exit-Script 0 'NotApplicable | TpmPresent=False' }
    if ($tpm.Major -lt 2) { Exit-Script 0 "NotApplicable | TpmPresent=True; TpmVersion=$($tpm.Major)" }
    if (-not $tpm.Ready) { Exit-Script 0 'NotApplicable | TpmPresent=True; TpmReady=False' }

    $status = Get-HealthCertStatus
    $task   = Get-RetrievalTask
    $taskState = 'Missing'
    if ($task) { $taskState = [string]$task.State }

    if ($null -ne $status -and $status -eq $HealthyStatus) {
        Exit-Script 0 "Healthy | TpmReady=True; HealthCertStatus=$status; TaskState=$taskState"
    }

    if ($null -eq $status) {
        Exit-Script 1 "HealthCertMissing | TpmReady=True; HealthCertStatus=None; TaskState=$taskState"
    }
    Exit-Script 1 "HealthCertStale | TpmReady=True; HealthCertStatus=$status; TaskState=$taskState"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
