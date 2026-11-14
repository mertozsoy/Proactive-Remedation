<#
.SYNOPSIS
  Detection script for missing or mismatched approved printer drivers.

.DESCRIPTION
  Compares exact driver names and installed INF SHA256 hashes with an approved list. Exits 1 for missing drivers, mismatches or errors and 0 when all approved drivers match. Does not change Point and Print policies.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedDrivers = @()

$PackageName = 'ApprovedPrinterDrivers'
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
function Assert-DriverConfiguration {
    if ($ApprovedDrivers.Count -eq 0) { throw 'ConfigureApprovedDrivers' }
    $names = @()
    foreach ($entry in $ApprovedDrivers) {
        if ([string]::IsNullOrWhiteSpace($entry.Name) -or $entry.Name -match '[\r\n]' -or $names -contains $entry.Name) { throw 'InvalidOrDuplicateDriverName' }
        if ($entry.InfSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'InvalidInfSha256' }
        if ($entry.SourceInf -notmatch '^[A-Za-z]:\\[^\r\n]*\.inf$' -or $entry.SourceInf -match '[*?"<>|]' -or $entry.SourceInf.Substring(2).Contains(':')) { throw 'UseLocalAbsoluteSourceInf' }
        $names += $entry.Name
    }
}
function Get-DriverDrift {
    $installed = @(Get-PrinterDriver -PrinterEnvironment 'Windows x64' -ErrorAction Stop)
    foreach ($entry in $ApprovedDrivers) {
        $driverMatches = @($installed | Where-Object { $_.Name -ieq $entry.Name })
        if ($driverMatches.Count -eq 0) {
            [pscustomobject]@{ Entry = $entry; Reason = 'Missing' }
            continue
        }
        $matchesApprovedInf = $false
        foreach ($driver in $driverMatches) {
            if (-not [string]::IsNullOrWhiteSpace($driver.InfPath) -and (Test-Path -LiteralPath $driver.InfPath -PathType Leaf)) {
                $hash = (Get-FileHash -LiteralPath $driver.InfPath -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($hash -ieq $entry.InfSha256) { $matchesApprovedInf = $true }
            }
        }
        if (-not $matchesApprovedInf) { [pscustomobject]@{ Entry = $entry; Reason = 'InfMismatch' } }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0.14393') { Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired' }
    $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
    if ($processors.Count -eq 0 -or @($processors | Where-Object { $_.Architecture -ne 9 }).Count -gt 0) { Exit-Script 0 'NotApplicable | Reason=RequiresX64Hardware' }
    Assert-DriverConfiguration
    $spooler = Get-Service -Name Spooler -ErrorAction Stop
    if ($spooler.Status -ne 'Running') { Exit-Script 1 'Blocked | Reason=SpoolerNotRunning' }
    $drift = @(Get-DriverDrift)
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | Approved=$($ApprovedDrivers.Count); DriverDrift=0; Policy=Unchanged" }
    $missing = @($drift | Where-Object { $_.Reason -eq 'Missing' }).Count
    $mismatch = @($drift | Where-Object { $_.Reason -eq 'InfMismatch' }).Count
    Exit-Script 1 "Drift | Missing=$missing; InfMismatch=$mismatch; Policy=Unchanged"
}
catch { Exit-Script 1 "Error | Phase=Detect; ErrorType=$($_.Exception.GetType().Name); Action=CheckConfigurationAndDriverState" }
