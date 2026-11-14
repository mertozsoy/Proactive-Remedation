<#
.SYNOPSIS
  Detection script for a stopped Application Identity service.

.DESCRIPTION
  Checks AppIDSvc without changing its configuration. Exits 1 if the service is not running, 0 if running or absent.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName = 'AppIDSvc'

$PackageName = 'ApplicationIdentity'
$Phase = 'Detect'
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
    $serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($null -eq $serviceInfo) { Exit-Script 0 'NotApplicable | Service=AppIDSvc; Reason=ServiceMissing' }
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($serviceInfo.StartMode -eq 'Disabled') {
        Exit-Script 1 "Drift | Service=AppIDSvc; State=$($service.Status); StartMode=Disabled; Action=ReviewServiceConfiguration"
    }
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Exit-Script 1 "Drift | Service=AppIDSvc; State=$($service.Status); StartMode=$($serviceInfo.StartMode)"
    }
    Exit-Script 0 "Healthy | Service=AppIDSvc; State=Running; StartMode=$($serviceInfo.StartMode)"
}
catch { Exit-Script 1 "Error: Service=AppIDSvc; HResult=$($_.Exception.HResult)" }
