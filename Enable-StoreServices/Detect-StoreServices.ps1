<#
.SYNOPSIS
  Detection script for disabled Microsoft Store deployment services.

.DESCRIPTION
  Checks InstallService, ClipSVC and AppXSvc on Windows clients. Exits 1 for disabled or missing services and 0 when all are enabled. Stopped demand-start services are healthy. Policy ownership exclusions must be supplied by the administrator.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyManagedServices = @()
$CimTimeoutSeconds = 30

$PackageName = 'StoreServices'
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
    $ErrorActionPreference = 'Stop'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0') {
        Exit-Script 0 'NotApplicable | Reason=UnsupportedOS'
    }
    $serviceNames = @('InstallService', 'ClipSVC', 'AppXSvc')
    $services = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='InstallService' OR Name='ClipSVC' OR Name='AppXSvc'" -OperationTimeoutSec $CimTimeoutSeconds)
    $disabled = @()
    $missing = @()
    $managed = @()
    foreach ($name in $serviceNames) {
        $service = $services | Where-Object { $_.Name -eq $name }
        if ($null -eq $service) { $missing += $name; continue }
        Write-IRTLog ('Service={0}; StartMode={1}; State={2}' -f $name, $service.StartMode, $service.State)
        if ($service.StartMode -eq 'Disabled') {
            $disabled += $name
            if ($PolicyManagedServices -contains $name) { $managed += $name }
        }
    }
    if ($disabled.Count -gt 0 -or $missing.Count -gt 0) {
        Exit-Script 1 "Drift | Disabled=$($disabled -join ','); Missing=$($missing -join ','); PolicyManaged=$($managed -join ',')"
    }
    Exit-Script 0 'Healthy | Disabled=0; Missing=0; Checked=3'
}
catch { Exit-Script 1 ('Error: Failed | Reason=ServiceQueryFailed; HResult={0}' -f $_.Exception.HResult) }
