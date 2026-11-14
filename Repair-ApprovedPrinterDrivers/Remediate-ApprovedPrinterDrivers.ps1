<#
.SYNOPSIS
  Remediation script for preinstalling approved printer drivers as SYSTEM.

.DESCRIPTION
  Validates local approved INF hashes, stages signed drivers with PnPUtil, registers them with Add-PrinterDriver and checks installed INF hashes. Existing driver changes require explicit opt-in. Exits 0 only for a verified healthy or fixed state, 1 for blocked, pending or failed work. Never relaxes Point and Print restrictions or restarts services or the device.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedDrivers = @()
$ConfirmDeploymentApproved = $false
$AllowDriverUpdate = $false

$PackageName = 'ApprovedPrinterDrivers'
$Phase = 'Remediate'
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
function Get-ApprovedStoreInf {
    param([object]$Entry, [object[]]$StoreDrivers)
    $storeRoot = [IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository')) + '\'
    foreach ($driver in $StoreDrivers) {
        $path = [string]$driver.OriginalFileName
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ([IO.Path]::GetFileName($path) -ine [IO.Path]::GetFileName($Entry.SourceInf)) { continue }
        if (-not [IO.Path]::GetFullPath($path).StartsWith($storeRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ieq $Entry.InfSha256) { $path }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0.14393') { Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired' }
    $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
    if ($processors.Count -eq 0 -or @($processors | Where-Object { $_.Architecture -ne 9 }).Count -gt 0) { Exit-Script 0 'NotApplicable | Reason=RequiresX64Hardware' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { if ($identity.User.Value -ne 'S-1-5-18') { Exit-Script 1 'Failed | Reason=RequiresSystem' } }
    finally { $identity.Dispose() }
    Assert-DriverConfiguration
    $spooler = Get-Service -Name Spooler -ErrorAction Stop
    if ($spooler.Status -ne 'Running') { Exit-Script 1 'Blocked | Reason=SpoolerNotRunning' }
    $drift = @(Get-DriverDrift)
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | Approved=$($ApprovedDrivers.Count); DriverDrift=0; Policy=Unchanged" }
    if (-not $ConfirmDeploymentApproved) { Exit-Script 1 "Blocked | DriverDrift=$($drift.Count); Reason=ConfirmDeploymentApprovedRequired" }
    $mismatch = @($drift | Where-Object { $_.Reason -eq 'InfMismatch' }).Count
    if ($mismatch -gt 0 -and -not $AllowDriverUpdate) { Exit-Script 1 "Blocked | InfMismatch=$mismatch; Reason=DriverUpdateNotApproved" }
    foreach ($item in $drift) {
        $entry = $item.Entry
        $file = Get-Item -LiteralPath $entry.SourceInf -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'InvalidSourceInf' }
        if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash -ine $entry.InfSha256) { throw 'SourceInfHashMismatch' }
    }
    $pendingRestart = $false
    $completed = 0
    foreach ($item in $drift) {
        $entry = $item.Entry
        $pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
        & $pnputil /add-driver $entry.SourceInf 2>&1 | Out-Null
        $stageCode = $LASTEXITCODE
        Write-IRTLog "StageExitCode=$stageCode"
        if ($stageCode -eq 3010) { $pendingRestart = $true }
        elseif ($stageCode -ne 0) { Exit-Script 1 "Failed | StageExitCode=$stageCode; Completed=$completed; Policy=Unchanged" }
        $store = @(Get-WindowsDriver -Online -ErrorAction Stop)
        $infPaths = @(Get-ApprovedStoreInf -Entry $entry -StoreDrivers $store | Sort-Object -Unique)
        if ($infPaths.Count -ne 1) { Exit-Script 1 "Failed | Reason=StoreInfNotUnique; Matches=$($infPaths.Count); Completed=$completed" }
        Add-PrinterDriver -Name $entry.Name -InfPath $infPaths[0] -PrinterEnvironment 'Windows x64' -ErrorAction Stop | Out-Null
        $completed++
    }
    $remaining = @(Get-DriverDrift)
    if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | Remaining=$($remaining.Count); Completed=$completed; Policy=Unchanged" }
    if ($pendingRestart) { Exit-Script 1 "Pending | Installed=$completed; RestartRequired=True; Policy=Unchanged" }
    Exit-Script 0 "Fixed | Installed=$completed; Remaining=0; Policy=Unchanged"
}
catch { Exit-Script 1 "Error | Phase=Remediate; ErrorType=$($_.Exception.GetType().Name); Action=CheckSourceAndDriverState" }
