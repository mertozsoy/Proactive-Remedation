<#
.SYNOPSIS
  Detection script for a leftover Windows Update driver exclusion.

.DESCRIPTION
  Checks the documented machine policy value. Exits 1 for an exclusion or unexpected value type, 0 for no exclusion or an unsupported OS.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DriverRingsConfirmed = $false
$PolicySourcesRetired = $false

$PackageName = 'WUDriverExclusion'
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
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 14393) {
        Exit-Script 0 'NotApplicable | Reason=UnsupportedOS'
    }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $valueName = 'ExcludeWUDriversInQualityUpdate'
    if (-not (Test-Path -LiteralPath $policyPath)) { Exit-Script 0 'Healthy | Exclusion=Absent' }
    $key = Get-Item -LiteralPath $policyPath
    if ($key.GetValueNames() -notcontains $valueName) { Exit-Script 0 'Healthy | Exclusion=Absent' }
    if ($key.GetValueKind($valueName) -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        Exit-Script 1 'Drift | Reason=UnexpectedValueType; Action=ReviewPolicy'
    }
    $value = $key.GetValue($valueName)
    if ($value -eq 0) { Exit-Script 0 'Healthy | Exclusion=0' }
    if ($value -ne 1) { Exit-Script 1 'Drift | Reason=UnexpectedValueData; Action=ReviewPolicy' }
    Exit-Script 1 "Drift | Exclusion=1; DriverRingsConfirmed=$DriverRingsConfirmed; PolicySourcesRetired=$PolicySourcesRetired"
}
catch { Exit-Script 1 ('Error: OperationFailed | HResult={0}' -f $_.Exception.HResult) }
