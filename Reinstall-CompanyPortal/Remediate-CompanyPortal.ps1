<#
.SYNOPSIS
  Remediation script for a missing or broken Company Portal app registration.

.DESCRIPTION
  Provisions Company Portal from a staged msixbundle or removes a broken registration and provisioned entry so the Intune Store app can install the app again. Verifies the result and exits 0 when the device is healthy or the repair is staged for the next sign-in.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AppName           = 'Microsoft.CompanyPortal'
$ManifestName      = 'AppxManifest.xml'
$ProcessName       = 'CompanyPortal'
$PackagePath       = 'C:\ProgramData\IntuneRemediations\Source\Microsoft.CompanyPortal.msixbundle'
$DependencyPath    = @()
$LicensePath       = ''
$ResetForReinstall = $false

$PackageName = 'CompanyPortal'
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
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $AppName -or "$($_.PackageName)" -like "$AppName*" })
    $users    = 0
    $filesOk  = $true
    $versions = @()
    foreach ($package in $installed) {
        $users += @($package.PackageUserInformation | Where-Object { "$($_.InstallState)" -eq 'Installed' }).Count
        try { $versions += [version]$package.Version } catch { }
        if (-not $package.InstallLocation) { $filesOk = $false; continue }
        if (-not (Test-Path -LiteralPath (Join-Path $package.InstallLocation $ManifestName))) { $filesOk = $false }
    }
    if ($versions.Count -eq 0) {
        foreach ($entry in $provisioned) { try { $versions += [version]$entry.Version } catch { } }
    }
    $version = 'None'
    if ($versions.Count -gt 0) { $version = ($versions | Sort-Object -Descending | Select-Object -First 1).ToString() }

    $state = 'Healthy'
    if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) { $state = 'Missing' }
    elseif ($installed.Count -eq 0) { $state = 'NotRegistered' }
    elseif (-not $filesOk) { $state = 'Broken' }
    elseif ($users -eq 0) { $state = 'NotRegistered' }
    elseif ($provisioned.Count -eq 0) { $state = 'NotProvisioned' }

    [pscustomobject]@{
        State       = $state
        Installed   = $installed.Count
        Provisioned = ($provisioned.Count -gt 0)
        Users       = $users
        FilesOk     = $filesOk
        Version     = $version
    }
}

function New-PortalSummary { param($Portal)
    'Version={0}; Installed={1}; Users={2}; Provisioned={3}; Files={4}' -f $Portal.Version, $Portal.Installed, $Portal.Users, $(if ($Portal.Provisioned) { 'Yes' } else { 'No' }), $(if ($Portal.FilesOk) { 'OK' } else { 'Missing' })
}

function Remove-PortalRegistration {
    $result = [pscustomobject]@{ Removed = 0; Failed = 0 }
    foreach ($package in @(Get-AppxPackage -AllUsers -Name $AppName -ErrorAction Stop)) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            $result.Removed++
            Write-IRTLog "Removed registration $($package.PackageFullName)"
        }
        catch {
            $result.Failed++
            Write-IRTLog "Remove failed for $($package.PackageFullName): $($_.Exception.Message)" 'ERROR'
        }
    }
    $result
}

function Remove-PortalProvision {
    $result = [pscustomobject]@{ Removed = 0; Failed = 0 }
    foreach ($entry in @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $AppName -or "$($_.PackageName)" -like "$AppName*" })) {
        try {
            $name = $entry.PackageName
            if (-not $name) { $name = $AppName }
            Remove-AppxProvisionedPackage -Online -PackageName $name -ErrorAction Stop
            $result.Removed++
            Write-IRTLog "Removed provisioned entry $name"
        }
        catch {
            $result.Failed++
            Write-IRTLog "Provision removal failed: $($_.Exception.Message)" 'ERROR'
        }
    }
    $result
}

function Install-PortalProvision {
    $params = @{ Online = $true; PackagePath = $PackagePath }
    $dependencies = @($DependencyPath | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($dependencies.Count -gt 0) { $params['DependencyPackagePath'] = $dependencies }
    if ($LicensePath) { $params['LicensePath'] = $LicensePath } else { $params['SkipLicense'] = $true }
    Add-AppxProvisionedPackage @params -ErrorAction Stop | Out-Null
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | OS=Server' }

    $portal = Get-PortalState
    if ($portal.State -eq 'Healthy') { Exit-Script 0 "Healthy | $(New-PortalSummary -Portal $portal)" }

    $hasSource = $false
    if ($PackagePath) { $hasSource = Test-Path -LiteralPath $PackagePath }

    if ($portal.State -eq 'Broken' -or ($portal.State -eq 'NotRegistered' -and -not $portal.Provisioned)) {
        if (-not $hasSource -and -not $ResetForReinstall) {
            Exit-Script 1 "Reported | $(New-PortalSummary -Portal $portal); ResetForReinstall=No"
        }
        if (@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count -gt 0) {
            Exit-Script 1 "Deferred | State=$($portal.State); Reason=CompanyPortalOpen"
        }

        $cleanup = Remove-PortalRegistration
        if ($cleanup.Failed -gt 0) {
            Exit-Script 1 "Failed | State=$($portal.State); Removed=$($cleanup.Removed); Failed=$($cleanup.Failed); Reason=RegistrationLocked"
        }

        if ($hasSource) {
            $stage = Remove-PortalProvision
            if ($stage.Failed -gt 0) {
                Exit-Script 1 "Failed | State=$($portal.State); RegisteredRemoved=$($cleanup.Removed); ProvisionedFailed=$($stage.Failed)"
            }
            Install-PortalProvision
            $after = Get-PortalState
            if (-not $after.Provisioned) { Exit-Script 1 "Failed | State=$($after.State); Provisioned=No; Source=$PackagePath" }
            Exit-Script 0 "Repaired | $(New-PortalSummary -Portal $after); Removed=$($cleanup.Removed); Apply=next sign-in"
        }

        $stage = Remove-PortalProvision
        if ($stage.Failed -gt 0) {
            Exit-Script 1 "Failed | State=$($portal.State); RegisteredRemoved=$($cleanup.Removed); ProvisionedFailed=$($stage.Failed)"
        }
        $after = Get-PortalState
        if ($after.Installed -gt 0 -or $after.Provisioned) {
            Exit-Script 1 "Failed | State=$($after.State); $(New-PortalSummary -Portal $after); Reinstall=NotReady"
        }
        Exit-Script 0 "Reset | Installed=0; Provisioned=No; Removed=$($cleanup.Removed); Reinstall=Intune Store app (System); Apply=next check-in"
    }

    if ($portal.State -eq 'NotProvisioned') {
        if (-not $hasSource) { Exit-Script 1 "NotProvisioned | $(New-PortalSummary -Portal $portal); Action=stage bundle or assign Store app (System)" }
        Install-PortalProvision
        $after = Get-PortalState
        if (-not $after.Provisioned) { Exit-Script 1 "Failed | State=$($after.State); Provisioned=No" }
        Exit-Script 0 "Fixed | $(New-PortalSummary -Portal $after)"
    }

    if ($portal.State -eq 'Missing') {
        if (-not $hasSource) { Exit-Script 1 "Missing | $(New-PortalSummary -Portal $portal); Action=stage bundle or assign Store app (System)" }
        Install-PortalProvision
        $after = Get-PortalState
        if (-not $after.Provisioned) { Exit-Script 1 "Failed | State=$($after.State); Provisioned=No" }
        Exit-Script 0 "Fixed | $(New-PortalSummary -Portal $after); Apply=next sign-in"
    }

    if ($portal.State -eq 'NotRegistered') {
        Exit-Script 0 "Waiting | $(New-PortalSummary -Portal $portal); Apply=next sign-in"
    }

    Exit-Script 1 "Unknown | $(New-PortalSummary -Portal $portal)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
