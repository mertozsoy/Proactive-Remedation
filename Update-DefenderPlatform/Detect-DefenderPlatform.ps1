<#
.SYNOPSIS
  Detection script for an outdated Microsoft Defender Antivirus platform.

.DESCRIPTION
  Compares AMProductVersion with an approved minimum. Exits 1 for an outdated
  platform or a read failure, 0 when compliant or not applicable. Engine version
  is informational and is not used as the platform version.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumPlatformVersion = '4.18.26100.4'

$PackageName = 'DefenderPlatform'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
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
    $ErrorActionPreference = 'Stop'
    $minimum = [version]$MinimumPlatformVersion
    if ($minimum.Major -ne 4 -or $minimum.Minor -ne 18 -or $minimum.Revision -lt 0) {
        throw 'Invalid minimum platform version.'
    }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or ([version]$os.Version).Major -lt 10) {
        Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired'
    }
    $service = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | Reason=DefenderNotInstalled' }
    $status = Get-MpComputerStatus -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$status.AMProductVersion)) {
        throw 'Platform version unavailable.'
    }
    $platform = [version]$status.AMProductVersion
    if ($platform.Major -ne 4 -or $platform.Minor -ne 18 -or $platform.Revision -lt 0) {
        throw 'Invalid platform version.'
    }
    $details = "Platform=$platform; Minimum=$minimum; Engine=$($status.AMEngineVersion)"
    if ($platform -lt $minimum) { Exit-Script 1 "Drift | $details" }
    Exit-Script 0 "Healthy | $details"
}
catch { Exit-Script 1 ('Error: ReadFailed | HResult={0}' -f $_.Exception.HResult) }
