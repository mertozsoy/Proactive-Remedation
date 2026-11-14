<#
.SYNOPSIS
  Remediation script to remove Quick Assist from prohibited devices.

.DESCRIPTION
  Removes Quick Assist provisioning, all-user Appx registrations and the installed
  legacy capability. Verifies absence. Exits 0 on success, 1 on failure or deferral.
  Does not restart Windows, modify policies or block shared Remote Help endpoints.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$QuickAssistForbidden = $true
$DeferWhileRunning = $true

$PackageName = 'QuickAssist'
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
function Get-QuickAssistState {
    $apps = @(Get-AppxPackage -AllUsers -Name 'MicrosoftCorporationII.QuickAssist' -ErrorAction Stop)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq 'MicrosoftCorporationII.QuickAssist' })
    $capabilities = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -eq 'App.Support.QuickAssist~~~~0.0.1.0' })
    $legacyState = 'NotPresent'
    if ($capabilities.Count -gt 0) { $legacyState = [string]$capabilities[0].State }
    [pscustomobject]@{
        Apps = $apps
        Provisioned = $provisioned
        Capabilities = $capabilities
        LegacyState = $legacyState
        Present = ($apps.Count -gt 0 -or $provisioned.Count -gt 0 -or $legacyState -ne 'NotPresent')
    }
}

try {
    if (-not $QuickAssistForbidden) { Exit-Script 0 'NotApplicable | QuickAssistForbidden=False' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0') { Exit-Script 0 'NotApplicable | WindowsClient=False' }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error | Reason=Use64BitPowerShell' }
    $state = Get-QuickAssistState
    if (-not $state.Present) { Exit-Script 0 'Healthy | Installed=0; Provisioned=0; Legacy=NotPresent' }
    $running = @(Get-Process -Name 'QuickAssist' -ErrorAction SilentlyContinue)
    if ($DeferWhileRunning -and $running.Count -gt 0) { Exit-Script 1 'Deferred | Reason=QuickAssistRunning; Retry=NextSchedule' }
    if ($state.LegacyState -notin @('Installed', 'NotPresent')) {
        Exit-Script 1 "Deferred | Reason=CapabilityServicing; Legacy=$($state.LegacyState)"
    }
    $restartNeeded = $false
    foreach ($app in $state.Provisioned) {
        $result = Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction Stop
        if ($result.RestartNeeded) { $restartNeeded = $true }
        Write-IRTLog 'Quick Assist provisioning removed.'
    }
    $apps = @(Get-AppxPackage -AllUsers -Name 'MicrosoftCorporationII.QuickAssist' -ErrorAction Stop | Sort-Object -Property PackageFullName -Unique)
    foreach ($app in $apps) {
        Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
        Write-IRTLog 'Quick Assist all-user registration removed.'
    }
    foreach ($capability in @($state.Capabilities | Where-Object { $_.State -eq 'Installed' })) {
        $result = Remove-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
        if ($result.RestartNeeded) { $restartNeeded = $true }
        Write-IRTLog 'Quick Assist legacy capability removed.'
    }
    $after = Get-QuickAssistState
    $summary = 'Installed={0}; Provisioned={1}; Legacy={2}; RestartNeeded={3}' -f $after.Apps.Count, $after.Provisioned.Count, $after.LegacyState, $restartNeeded
    if ($after.Present) { Exit-Script 1 "Failed | $summary" }
    if ($restartNeeded) { Exit-Script 1 "PendingRestart | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 ('Error | HResult={0}; Reason=RemovalOrVerificationFailed' -f $_.Exception.HResult) }
