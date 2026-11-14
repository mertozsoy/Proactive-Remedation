<#
.SYNOPSIS
  Remediation script for Microsoft 365 Apps builds below an approved minimum.

.DESCRIPTION
  Requests an in-place Click-to-Run update to $MinimumBuild and verifies the installed
  build afterwards. Policy-managed targets and ConfigMgr managed devices are left alone.
  Exits 0 when the build reaches the minimum, 1 for report-only, deferred, pending or
  failed states.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumBuild = ''
$ProductIds = @('O365ProPlusRetail', 'O365BusinessRetail')
$EnableRemediation = $true
$CloseBlockingApps = $false
$VerifyTimeoutSeconds = 300
$BlockingProcessNames = @('winword', 'excel', 'powerpnt', 'outlook', 'onenote', 'msaccess', 'mspub', 'visio')

$PackageName = 'M365AppsMinimumBuild'
$Phase = 'Remediate'
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
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    if ($MinimumBuild -notmatch '^16\.0\.\d+\.\d+$') { Exit-Script 1 'Failed | Reason=ConfigureMinimumBuild' }
    if ($VerifyTimeoutSeconds -lt 30 -or $VerifyTimeoutSeconds -gt 1800) { Exit-Script 1 'Failed | Reason=InvalidVerifyTimeout' }
    $minimum = [version]$MinimumBuild
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $inventoryPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Inventory\Office\16.0'
    if (-not (Test-Path -LiteralPath $configPath)) { Exit-Script 0 'NotApplicable | Reason=NoClickToRun' }
    if (-not (Test-Path -LiteralPath $inventoryPath)) { Exit-Script 1 'Failed | Reason=OfficeInventoryMissing' }
    $config = Get-ItemProperty -LiteralPath $configPath
    $inventory = Get-ItemProperty -LiteralPath $inventoryPath
    $installedIds = @($inventory.OfficeProductReleaseIds | Where-Object { $_ })
    if ($installedIds.Count -eq 0) { Exit-Script 1 'Failed | Reason=ProductIdsMissing' }
    if (@($installedIds | Where-Object { $ProductIds -contains $_ }).Count -eq 0) {
        Exit-Script 0 'NotApplicable | Reason=NotMicrosoft365Apps'
    }
    if ([string]$inventory.OfficePackageVersion -notmatch '^16\.0\.\d+\.\d+$') {
        Exit-Script 1 'Failed | Reason=OfficeVersionUnreadable'
    }
    $installed = [version]$inventory.OfficePackageVersion
    if ($installed -ge $minimum) {
        Exit-Script 0 "Healthy | Installed=$installed; Minimum=$minimum; Action=None"
    }
    foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate', 'HKLM:\SOFTWARE\Policies\Microsoft\cloud\office\16.0\Common\officeupdate')) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $policyValue = (Get-ItemProperty -LiteralPath $path -Name 'TargetVersion' -ErrorAction SilentlyContinue).TargetVersion
        if ([string]$policyValue -match '^16\.0\.\d+\.\d+$' -and ([version]$policyValue) -lt $minimum) {
            Exit-Script 0 "NotApplicable | Reason=PolicyTargetBelowMinimum; Installed=$installed; Minimum=$minimum; PolicyTarget=$policyValue"
        }
    }
    if ([string]$config.OfficeMgmtCOM -match '^(true|1)$' -or (Get-Service -Name CcmExec -ErrorAction SilentlyContinue)) {
        Exit-Script 0 'NotApplicable | Reason=ConfigurationManager; Action=ReviewCentralManagement'
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Installed=$installed; Minimum=$minimum; Action=Disabled"
    }
    $clientPath = Join-Path $env:ProgramFiles 'Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe'
    if (-not (Test-Path -LiteralPath $clientPath -PathType Leaf)) { Exit-Script 1 'Failed | Reason=OfficeC2RClientMissing' }
    $service = Get-Service -Name ClickToRunSvc
    if ($service.Status -ne 'Running') {
        Start-Service -Name ClickToRunSvc
        $service = Get-Service -Name ClickToRunSvc
        if ($service.Status -ne 'Running') { Exit-Script 1 'Failed | Reason=ClickToRunServiceStopped' }
    }
    $blocking = @(Get-Process -Name $BlockingProcessNames -ErrorAction SilentlyContinue)
    if ($blocking.Count -gt 0) {
        if (-not $CloseBlockingApps) {
            Exit-Script 1 "Deferred | Installed=$installed; Minimum=$minimum; Reason=OfficeAppsRunning; Processes=$($blocking.Count); Action=RetryLater"
        }
        $blocking | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 10
    }
    Write-IRTLog "Update requested | Installed=$installed; Target=$minimum"
    $process = Start-Process -FilePath $clientPath -ArgumentList "/update user updatetoversion=$minimum" -WindowStyle Hidden -PassThru -ErrorAction Stop
    if (-not $process.WaitForExit(600000)) {
        Exit-Script 1 "Pending | Installed=$installed; Target=$minimum; Reason=ClientTimeout; Action=RetryLater"
    }
    $process.Refresh()
    $clientExit = $process.ExitCode
    $current = $installed
    $deadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
    do {
        Start-Sleep -Seconds 15
        $value = (Get-ItemProperty -LiteralPath $inventoryPath -ErrorAction SilentlyContinue).OfficePackageVersion
        if ([string]$value -match '^16\.0\.\d+\.\d+$') { $current = [version]$value }
        if ($current -ge $minimum) { break }
    } while ((Get-Date) -lt $deadline)
    if ($current -ge $minimum) {
        Exit-Script 0 "Fixed | From=$installed; To=$current; Minimum=$minimum; ClientExit=$clientExit"
    }
    if ($clientExit -ne 0) {
        Exit-Script 1 "Failed | From=$installed; Current=$current; Target=$minimum; ClientExit=$clientExit"
    }
    Exit-Script 1 "Pending | From=$installed; Current=$current; Target=$minimum; ClientExit=$clientExit; Action=RetryLater"
}
catch { Exit-Script 1 ('Failed | Operation=Update; HResult={0}' -f $_.Exception.HResult) }
