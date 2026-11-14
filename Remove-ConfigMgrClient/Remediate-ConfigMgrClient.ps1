<#
.SYNOPSIS
  Remediation script for approved ConfigMgr client removal.

.DESCRIPTION
  Defaults to report mode. With both approval switches enabled, runs the signed local CCMSetup.exe /uninstall and verifies the selected checks. Exits 0 only when those checks are clear or not applicable, 1 for report mode, remaining findings or errors. Residual cleanup is report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$IntuneOnlyMigrationApproved = $false
$UninstallTimeoutSeconds = 600
$VerificationSeconds = 60
$CimTimeoutSeconds = 20

$PackageName = 'ConfigMgrClient'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}
function Get-ClientState {
    $service = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='CcmExec'" -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop)
    $setup = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='ccmsetup.exe'" -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop)
    $paths = [ordered]@{
        CCM = (Join-Path $env:windir 'CCM')
        CCMSetup = (Join-Path $env:windir 'ccmsetup')
        SMSCFG = (Join-Path $env:windir 'SMSCFG.ini')
        CCMKey = 'HKLM:\SOFTWARE\Microsoft\CCM'
        CCMSetupKey = 'HKLM:\SOFTWARE\Microsoft\CCMSetup'
        SMSKey = 'HKLM:\SOFTWARE\Microsoft\SMS'
    }
    $residuals = @($paths.Keys | Where-Object { Test-Path -LiteralPath $paths[$_] -ErrorAction Stop })
    $serviceState = 'Absent'
    if ($service.Count -gt 0) { $serviceState = [string]$service[0].State }
    $labels = 'None'
    if ($residuals.Count -gt 0) { $labels = $residuals -join ',' }
    [pscustomobject]@{
        ClientPresent = ($service.Count -gt 0)
        SetupCount = $setup.Count
        ResidualCount = $residuals.Count
        Summary = "CcmExec=$serviceState; SetupProcesses=$($setup.Count); Residuals=$labels"
    }
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 0 'NotApplicable | Reason=Requires64BitPowerShell' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec $CimTimeoutSeconds -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=NotWorkstation' }
    $state = Get-ClientState
    if ($state.SetupCount -gt 0) { Exit-Script 1 "Busy | $($state.Summary); Action=WaitForSetup" }
    if (-not $state.ClientPresent) {
        if ($state.ResidualCount -gt 0) { Exit-Script 1 "NeedsReview | $($state.Summary); Cleanup=ReportOnly" }
        Exit-Script 0 "Healthy | $($state.Summary); Scope=SelectedChecksOnly"
    }
    if (-not $EnableRemediation -or -not $IntuneOnlyMigrationApproved) {
        Exit-Script 1 "ReportOnly | $($state.Summary); Action=ApproveIntuneOnlyMigrationAndEnableRemediation"
    }
    if ($UninstallTimeoutSeconds -lt 30 -or $UninstallTimeoutSeconds -gt 900 -or $VerificationSeconds -lt 0 -or $VerificationSeconds -gt 120) {
        Exit-Script 1 'Failed | Reason=InvalidTimeoutConfiguration'
    }
    $setupPath = Join-Path $env:windir 'ccmsetup\ccmsetup.exe'
    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf -ErrorAction Stop)) {
        Exit-Script 1 "NeedsReview | $($state.Summary); Reason=UninstallerMissing; Cleanup=ReportOnly"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $setupPath -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
        Exit-Script 1 'Failed | Reason=UninstallerSignatureInvalid; Action=ReviewTrustedClientSource'
    }
    $publisher = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    if ($publisher -ne 'Microsoft Corporation') { Exit-Script 1 'Failed | Reason=UnexpectedUninstallerPublisher' }
    $state = Get-ClientState
    if ($state.SetupCount -gt 0) { Exit-Script 1 "Busy | $($state.Summary); Action=WaitForSetup" }
    if (-not $state.ClientPresent) { Exit-Script 1 "NeedsReview | $($state.Summary); Reason=ClientStateChanged" }
    Write-IRTLog 'Starting approved CCMSetup uninstall; residual cleanup remains report only.'
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $setupPath -ArgumentList '/uninstall' -WorkingDirectory (Split-Path -Path $setupPath -Parent) -PassThru -WindowStyle Hidden -ErrorAction Stop
    if (-not $process.WaitForExit([int]($UninstallTimeoutSeconds * 1000))) {
        Exit-Script 1 'Failed | Reason=UninstallTimeout; Action=ReviewCCMSetupLog; ProcessTerminated=False'
    }
    $process.Refresh()
    $returnCode = $process.ExitCode
    do {
        $state = Get-ClientState
        if ($state.SetupCount -eq 0) { break }
        if ($timer.Elapsed.TotalSeconds -ge $UninstallTimeoutSeconds) {
            Exit-Script 1 'Failed | Reason=SetupStillRunning; Action=ReviewCCMSetupLog; ProcessTerminated=False'
        }
        Start-Sleep -Seconds 5
    } while ($true)
    if ($returnCode -ne 0) {
        Exit-Script 1 "Failed | UninstallExitCode=$returnCode; $($state.Summary); Action=ReviewCCMSetupLog; RestartInitiated=False"
    }
    $verifyTimer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($state.ClientPresent -and $verifyTimer.Elapsed.TotalSeconds -lt $VerificationSeconds) {
        Start-Sleep -Seconds 5
        $state = Get-ClientState
    }
    if ($state.ClientPresent -or $state.SetupCount -gt 0) {
        Exit-Script 1 "Failed | UninstallExitCode=$returnCode; $($state.Summary); Action=ReviewCCMSetupLog"
    }
    if ($state.ResidualCount -gt 0) {
        Exit-Script 1 "NeedsReview | UninstallExitCode=0; $($state.Summary); Cleanup=ReportOnly"
    }
    Exit-Script 0 "Fixed | UninstallExitCode=0; $($state.Summary); Scope=SelectedChecksOnly"
}
catch { Exit-Script 1 ('Error: OperationFailed | HResult={0}; Action=ReviewCimAccessAndCCMSetupLog' -f $_.Exception.HResult) }
