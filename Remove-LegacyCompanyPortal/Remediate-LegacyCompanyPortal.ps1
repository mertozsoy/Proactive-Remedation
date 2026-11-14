<#
.SYNOPSIS
  Remediation script for a per-user Company Portal install that blocks the system install.

.DESCRIPTION
  Removes the per-user Company Portal copy for all users when no provisioned package exists, then checks the result. Waits for the next run if Company Portal is open. Exits 0 when no per-user copy is left.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AppName     = 'Microsoft.CompanyPortal'
$ProcessName = 'CompanyPortal'

$PackageName = 'LegacyCompanyPortal'
$Phase       = 'Remediate'
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
    if ($state.Installed.Count -eq 0) { Exit-Script 0 'Remediated | CompanyPortal=NotInstalled; Removed=0' }
    if ($state.Provisioned)           { Exit-Script 0 "Skipped | Provisioned=Yes; Version=$($state.Version)" }

    if (@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count -gt 0) {
        Exit-Script 1 'Deferred | Reason=CompanyPortalOpen'
    }

    $removed = 0
    $failed  = New-Object System.Collections.Generic.List[string]
    foreach ($package in $state.Installed) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            $removed++
            Write-IRTLog "Removed $($package.PackageFullName)"
        }
        catch {
            $failed.Add($package.PackageFullName)
            Write-IRTLog "Remove failed for $($package.PackageFullName): $($_.Exception.Message)" 'ERROR'
        }
    }

    $after = Get-PortalState
    if ($after.Installed.Count -gt 0) { Exit-Script 1 "Failed | Removed=$removed; Remaining=$($after.Installed.Count); Users=$($after.UserCount)" }
    Exit-Script 0 "Remediated | Removed=$removed; Remaining=0; Next=IntuneSystemInstall"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
