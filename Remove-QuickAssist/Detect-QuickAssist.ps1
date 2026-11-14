<#
.SYNOPSIS
  Detection script for Quick Assist on devices where it is forbidden.

.DESCRIPTION
  Checks all-user Appx registrations, provisioning and the legacy Windows capability.
  Exits 1 if Quick Assist is present or servicing is pending, 0 if absent or out of scope.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$QuickAssistForbidden = $true

$PackageName = 'QuickAssist'
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
    $summary = 'Installed={0}; Provisioned={1}; Legacy={2}' -f $state.Apps.Count, $state.Provisioned.Count, $state.LegacyState
    if ($state.Present) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error | HResult={0}; Reason=InventoryFailed' -f $_.Exception.HResult) }
