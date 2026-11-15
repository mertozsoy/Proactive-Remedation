<#
.SYNOPSIS
  Remediation script for the Remote Registry service on managed clients.

.DESCRIPTION
  Stops the RemoteRegistry service when it is running, sets its start type to Disabled and verifies the result. Exits 0 when the service is disabled and stopped, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$ServiceName       = 'RemoteRegistry'
$ServiceKey        = 'HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry'
$ExpectedStart     = 4
$BackupRoot        = Join-Path $env:ProgramData 'IntuneRemediations\Backup\RemoteRegistry'

$PackageName = 'RemoteRegistry'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-StartTypeText { param($Value)
    if ($null -eq $Value) { return 'Unknown' }
    switch ([int]$Value) {
        0 { return 'Boot' }
        1 { return 'System' }
        2 { return 'Automatic' }
        3 { return 'Manual' }
        4 { return 'Disabled' }
        default { return ('Value{0}' -f $Value) }
    }
}

function Get-RemoteRegistryState {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) { return $null }

    $start = $null
    try { $start = (Get-ItemProperty -LiteralPath $ServiceKey -Name 'Start' -ErrorAction Stop).Start } catch { $start = $null }

    [pscustomobject]@{
        StartValue = $start
        StartType  = (Get-StartTypeText $start)
        Status     = [string]$service.Status
    }
}

function Format-ServiceState { param($State)
    return ('Service={0}; Start={1}; State={2}' -f $ServiceName, $State.StartType, $State.Status)
}

function Save-RegistryBackup {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $target = Join-Path $BackupRoot ('RemoteRegistry-{0}.reg' -f $stamp)
    & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Services\RemoteRegistry' $target /y | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-IRTLog 'Registry backup skipped, key not readable' 'WARN' }
}

try {
    $state = Get-RemoteRegistryState
    if ($null -eq $state) { Exit-Script 0 'NotApplicable | Service=RemoteRegistry; Reason=NotFound' }

    $summary = Format-ServiceState -State $state
    $drift = ($null -eq $state.StartValue -or [int]$state.StartValue -ne $ExpectedStart -or $state.Status -eq 'Running')

    if (-not $drift) { Exit-Script 0 "Healthy | $summary" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | $summary" }

    Write-IRTLog "Drift before remediation: $summary"
    Save-RegistryBackup

    $stopped = $false
    if ($state.Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        $stopped = $true
        Write-IRTLog 'RemoteRegistry service stopped'
    }

    if ($null -eq $state.StartValue -or [int]$state.StartValue -ne $ExpectedStart) {
        Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop
        Write-IRTLog 'RemoteRegistry start type set to Disabled'
    }

    $after = Get-RemoteRegistryState
    if ($null -eq $after) { Exit-Script 1 "Failed | Service=RemoteRegistry; Reason=StateUnreadable" }

    $result = '{0}; Stopped={1}' -f (Format-ServiceState -State $after), $stopped
    if ($null -ne $after.StartValue -and [int]$after.StartValue -eq $ExpectedStart -and $after.Status -ne 'Running') {
        Exit-Script 0 "Fixed | $result"
    }
    Exit-Script 1 "Failed | $result"
}
catch {
    Exit-Script 1 ('Error: RemediationFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
