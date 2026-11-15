<#
.SYNOPSIS
  Detection script for a stopped or disabled Microsoft Office Click-to-Run service.

.DESCRIPTION
  Reads the ClickToRunSvc service state and startup mode on a device where Microsoft 365 Apps
  is installed by Click-to-Run. Exits 1 if the service is disabled or not running, 0 otherwise.
  Exits 0 with NotApplicable when the Office Click-to-Run service is not installed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName = 'ClickToRunSvc'
$CheckStoppedState = $true
$OfficeConfigKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

$PackageName = 'ClickToRunService'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

try {
    $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient' }

    $service = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | Reason=ServiceMissing' }

    $officeVersion = 'Unknown'
    if (Test-Path -LiteralPath $OfficeConfigKey) {
        $config = Get-ItemProperty -LiteralPath $OfficeConfigKey -ErrorAction SilentlyContinue
        $reported = [string]$config.VersionToReport
        if ($reported -match '^\d+\.\d+\.\d+\.\d+$') { $officeVersion = $reported }
    }

    $summary = 'Service={0}; State={1}; StartMode={2}; OfficeVersion={3}' -f $service.Name, $service.State, $service.StartMode, $officeVersion

    if ($service.StartMode -eq 'Disabled') { Exit-Script 1 "Drift | $summary" }
    if ($CheckStoppedState -and $service.State -ne 'Running') { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Detect; HResult=$($_.Exception.HResult)" }
