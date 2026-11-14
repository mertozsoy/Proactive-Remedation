<#
.SYNOPSIS
  Remediation script for a stopped Application Identity service.

.DESCRIPTION
  Starts AppIDSvc and verifies Running within a bounded wait. Does not change startup type or AppLocker rules. Exits 0 after verification, 1 if blocked or unsuccessful.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName = 'AppIDSvc'
$WaitSeconds = 30

$PackageName = 'ApplicationIdentity'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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

try {
    if ($WaitSeconds -lt 1 -or $WaitSeconds -gt 120) { throw 'InvalidWaitSeconds' }
    $serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($null -eq $serviceInfo) { Exit-Script 0 'NotApplicable | Service=AppIDSvc; Reason=ServiceMissing' }
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($serviceInfo.StartMode -eq 'Disabled') {
        Exit-Script 1 "Failed | Service=AppIDSvc; State=$($service.Status); StartMode=Disabled; Action=ReviewServiceConfiguration"
    }
    if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Exit-Script 0 "Healthy | Service=AppIDSvc; State=Running; StartMode=$($serviceInfo.StartMode)"
    }
    $timeout = [TimeSpan]::FromSeconds($WaitSeconds)
    if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::StopPending) {
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, $timeout)
        $service.Refresh()
    }
    if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        Start-Service -Name $ServiceName -ErrorAction Stop
    }
    elseif ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::StartPending) {
        Exit-Script 1 "Failed | Service=AppIDSvc; State=$($service.Status); Reason=UnexpectedServiceState"
    }
    $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, $timeout)
    $service.Refresh()
    $verified = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($null -eq $verified -or $verified.StartMode -eq 'Disabled' -or $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Exit-Script 1 'Failed | Service=AppIDSvc; Reason=VerificationFailed'
    }
    Exit-Script 0 "Fixed | Service=AppIDSvc; State=Running; StartMode=$($verified.StartMode)"
}
catch { Exit-Script 1 "Error: Service=AppIDSvc; HResult=$($_.Exception.HResult)" }
