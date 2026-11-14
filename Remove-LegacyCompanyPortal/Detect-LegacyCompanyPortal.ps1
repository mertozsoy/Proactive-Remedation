<#
.SYNOPSIS
  Detection script for a per-user Company Portal install that blocks the system install.

.DESCRIPTION
  Checks whether Company Portal is installed only for individual users and is not provisioned for the device. Exits 1 when a per-user copy exists without a provisioned package.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AppName     = 'Microsoft.CompanyPortal'
$ProcessName = 'CompanyPortal'

$PackageName = 'LegacyCompanyPortal'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-PortalState {
    $installed   = @(Get-AppxPackage -AllUsers -Name $AppName -ErrorAction Stop)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $AppName })
    $userCount   = 0
    foreach ($package in $installed) {
        $userCount += @($package.PackageUserInformation | Where-Object { "$($_.InstallState)" -eq 'Installed' }).Count
    }
    [pscustomobject]@{
        Installed   = $installed
        Provisioned = $provisioned.Count -gt 0
        UserCount   = $userCount
        Version     = ($installed | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1).Version
    }
}

try {
    $state = Get-PortalState
    if ($state.Installed.Count -eq 0) { Exit-Script 0 'NotApplicable | CompanyPortal=NotInstalled' }

    $summary = 'Version={0}; Users={1}; Provisioned={2}' -f $state.Version, $state.UserCount, $(if ($state.Provisioned) { 'Yes' } else { 'No' })
    if (-not $state.Provisioned) { Exit-Script 1 "PerUserOnly | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
