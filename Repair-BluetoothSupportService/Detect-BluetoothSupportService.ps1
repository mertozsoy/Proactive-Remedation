<#
.SYNOPSIS
  Detection script for a stopped or disabled Bluetooth Support Service.

.DESCRIPTION
  Checks the bthserv service state and startup mode on devices that have a Bluetooth radio.
  Exits 1 if the service is disabled or stopped, 0 if it runs. Exits 0 with NotApplicable
  when the device has no Bluetooth radio or the service is missing.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName = 'bthserv'
$CheckStoppedState = $true
$RequireBluetoothRadio = $true

$PackageName = 'BluetoothSupportService'
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

function Get-BluetoothRadioCount {
    $count = 0
    if (Get-Command -Name 'Get-PnpDevice' -ErrorAction SilentlyContinue) {
        $count = @(Get-PnpDevice -Class 'Bluetooth' -PresentOnly -ErrorAction SilentlyContinue).Count
    }
    else {
        $count = @(Get-CimInstance -ClassName 'Win32_PnPEntity' -ErrorAction SilentlyContinue | Where-Object { $_.PNPClass -eq 'Bluetooth' }).Count
    }
    $count
}

try {
    $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient' }

    $service = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | Reason=ServiceMissing' }

    $radioCount = 0
    if ($RequireBluetoothRadio) { $radioCount = Get-BluetoothRadioCount }
    if ($RequireBluetoothRadio -and $radioCount -eq 0) {
        Exit-Script 0 'NotApplicable | Reason=NoBluetoothRadio'
    }

    $summary = 'Service={0}; State={1}; StartMode={2}; Radios={3}' -f $service.Name, $service.State, $service.StartMode, $radioCount
    if ($service.StartMode -eq 'Disabled') { Exit-Script 1 "Drift | $summary" }
    if ($CheckStoppedState -and $service.State -ne 'Running') { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Detect; HResult=$($_.Exception.HResult)" }
