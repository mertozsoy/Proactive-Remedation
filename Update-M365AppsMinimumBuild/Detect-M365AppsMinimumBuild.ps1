<#
.SYNOPSIS
  Detection script for Microsoft 365 Apps builds below an approved minimum.

.DESCRIPTION
  Reads the Click-to-Run inventory and compares the installed build with $MinimumBuild.
  Also reads an Office policy target version when one is configured. Exits 1 when the
  build is below the minimum, 0 for healthy, excluded or not applicable states.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumBuild = ''
$ProductIds = @('O365ProPlusRetail', 'O365BusinessRetail')

$PackageName = 'M365AppsMinimumBuild'
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
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $configPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $inventoryPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Inventory\Office\16.0'
    if (-not (Test-Path -LiteralPath $configPath)) { Exit-Script 0 'NotApplicable | Reason=NoClickToRun' }
    if (-not (Test-Path -LiteralPath $inventoryPath)) { Exit-Script 1 'Failed | Reason=OfficeInventoryMissing' }
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
    $policyTarget = ''
    foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate', 'HKLM:\SOFTWARE\Policies\Microsoft\cloud\office\16.0\Common\officeupdate')) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $policyValue = (Get-ItemProperty -LiteralPath $path -Name 'TargetVersion' -ErrorAction SilentlyContinue).TargetVersion
        if ([string]$policyValue -match '^16\.0\.\d+\.\d+$') { $policyTarget = [string]$policyValue }
    }
    if (-not $MinimumBuild) {
        Exit-Script 0 "Inventory | Installed=$installed; Minimum=NotConfigured; PolicyTarget=$policyTarget"
    }
    if ($MinimumBuild -notmatch '^16\.0\.\d+\.\d+$') { Exit-Script 1 'Failed | Reason=InvalidMinimumBuild' }
    $minimum = [version]$MinimumBuild
    if ($policyTarget -and ([version]$policyTarget) -lt $minimum) {
        Exit-Script 0 "NotApplicable | Reason=PolicyTargetBelowMinimum; Installed=$installed; Minimum=$minimum; PolicyTarget=$policyTarget"
    }
    if ($installed -lt $minimum) {
        Exit-Script 1 "Drift | Installed=$installed; Minimum=$minimum; PolicyTarget=$policyTarget; Products=$($installedIds -join ',')"
    }
    Exit-Script 0 "Healthy | Installed=$installed; Minimum=$minimum; PolicyTarget=$policyTarget"
}
catch { Exit-Script 1 ('Failed | Operation=Detect; HResult={0}' -f $_.Exception.HResult) }
