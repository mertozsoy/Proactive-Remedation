<#
.SYNOPSIS
  Detection script for ConfigMgr client migration findings.

.DESCRIPTION
  Checks CcmExec, CCMSetup processes and selected residual paths. Exits 1 for client presence, setup activity or residuals requiring review, 0 when the selected checks are clear or not applicable. Does not determine migration readiness.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$CimTimeoutSeconds = 20

$PackageName = 'ConfigMgrClient'
$Phase = 'Detect'
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
    if ($state.ClientPresent) { Exit-Script 1 "Drift | $($state.Summary); Action=ReviewMigrationApproval" }
    if ($state.ResidualCount -gt 0) { Exit-Script 1 "NeedsReview | $($state.Summary); Cleanup=ReportOnly" }
    Exit-Script 0 "Healthy | $($state.Summary); Scope=SelectedChecksOnly"
}
catch { Exit-Script 1 ('Error: QueryFailed | HResult={0}; Action=ReviewCimAndAccess' -f $_.Exception.HResult) }
