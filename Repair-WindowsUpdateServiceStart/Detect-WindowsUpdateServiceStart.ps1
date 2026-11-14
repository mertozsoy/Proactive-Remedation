<#
.SYNOPSIS
  Detection script for disabled Windows Update services.

.DESCRIPTION
  Checks service startup configuration without requiring demand-start services to run.
  Exits 1 for disabled or missing services and 0 when all four services are enabled.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceNames = @('wuauserv', 'UsoSvc', 'BITS', 'WaaSMedicSvc')

$PackageName = 'WindowsUpdateServiceStart'
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
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 17763) {
        Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient1809OrLater'
    }
    $findings = @()
    $states = @()
    foreach ($name in $ServiceNames) {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
        if ($null -eq $service) {
            $findings += "$name=Missing"
            $states += "$name=Missing"
            continue
        }
        $states += ('{0}={1}' -f $name, $service.StartMode)
        if ($service.StartMode -notin @('Auto', 'Manual')) {
            $findings += ('{0}={1}' -f $name, $service.StartMode)
        }
    }
    if ($findings.Count -gt 0) {
        Exit-Script 1 "Drift | Issues=$($findings -join ','); Services=$($states -join ',')"
    }
    Exit-Script 0 "Healthy | Services=$($states -join ','); Scope=StartupOnly"
}
catch { Exit-Script 1 "Error: Failed | Operation=Detect; HResult=$($_.Exception.HResult)" }
