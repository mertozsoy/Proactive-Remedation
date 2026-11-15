<#
.SYNOPSIS
  Detection script for a disabled WinHTTP Auto-Proxy service that leaves Windows Connection Manager broken.

.DESCRIPTION
  Reads the start mode of WinHttpAutoProxySvc and checks whether WcmSvc still lists it as a dependency. Also reports a stopped connection manager. Exits 1 when the service is disabled with an active dependency or the connection manager is not running, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName            = 'WinHttpAutoProxySvc'
$ConnectionsServiceName = 'WcmSvc'
$RequireDependency      = $true
$CheckConnectionManager = $true
$ManagedByPolicy        = $false

$PackageName = 'WinHttpAutoProxy'
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

function Get-ServiceRecord {
    param([string]$Name)
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($null -eq $service) { return $null }
    return [pscustomobject]@{ StartMode = [string]$service.StartMode; State = [string]$service.State }
}

function Get-DependencyPresent {
    $value = $null
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$ConnectionsServiceName"
        $value = (Get-ItemProperty -LiteralPath $path -Name 'DependOnService' -ErrorAction Stop).DependOnService
    }
    catch { return $false }
    if ($null -eq $value) { return $false }
    return (@($value) -contains $ServiceName)
}

try {
    if ($ManagedByPolicy) { Exit-Script 0 'NotApplicable | Reason=ManagedByPolicy; Action=None' }

    $service = Get-ServiceRecord -Name $ServiceName
    if ($null -eq $service) { Exit-Script 0 "NotApplicable | Reason=ServiceMissing; Service=$ServiceName" }

    $connection = Get-ServiceRecord -Name $ConnectionsServiceName
    $connectionState = 'Missing'
    if ($null -ne $connection) { $connectionState = $connection.State }

    $dependency = Get-DependencyPresent

    if ($service.StartMode -eq 'Disabled') {
        if ($RequireDependency -and -not $dependency) {
            Exit-Script 0 "NotApplicable | Service=Disabled; Wcm=$connectionState; Dependency=False; Reason=NoDependency"
        }
        Exit-Script 1 "Drift | Service=Disabled; Wcm=$connectionState; Dependency=$dependency; Reason=ServiceDisabled"
    }

    if ($CheckConnectionManager -and $null -ne $connection -and $dependency -and $connection.State -ne 'Running') {
        Exit-Script 1 "Drift | Service=$($service.StartMode); Wcm=$connectionState; Dependency=$dependency; Reason=ConnectionManagerStopped"
    }

    Exit-Script 0 "Healthy | Service=$($service.StartMode); Wcm=$connectionState; Dependency=$dependency"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
