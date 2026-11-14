<#
.SYNOPSIS
  Detection script for a missing or broken Company Portal app registration.

.DESCRIPTION
  Reads the Microsoft.CompanyPortal app for all users and the provisioned entry for the device. Exits 1 if the app is missing, not provisioned, not registered for any user or its install folder is incomplete. Exits 0 if the app is healthy.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AppName      = 'Microsoft.CompanyPortal'
$ManifestName = 'AppxManifest.xml'

$PackageName = 'CompanyPortal'
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

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | OS=Server' }

    $portal  = Get-PortalState
    $summary = New-PortalSummary -Portal $portal

    if ($portal.State -eq 'Healthy') { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 1 "$($portal.State) | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
