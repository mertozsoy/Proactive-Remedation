<#
.SYNOPSIS
  Remediation script to remove the retired Remote Desktop client after moving to Windows App.

.DESCRIPTION
  Removes the Remote Desktop Store app for all users, its provisioned entry and
  the MSI client named Remote Desktop. Verifies that nothing remains.
  Exits 0 when clean, 1 when removal or verification fails.
  Does not restart Windows and does not sign users out.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$OnlyWhenWindowsAppInstalled = $true
$RemoveProvisioned = $true
$RemoveMsiClient = $true
$DeferWhileRunning = $true
$WindowsAppNamePattern = '*WindowsApp*'
$LegacyNamePattern = '*RemoteDesktop*'
$LegacyPublisherPattern = 'CN=Microsoft*'
$LegacyMsiDisplayName = 'Remote Desktop'
$LegacyProcessNames = @('msrdc')

$PackageName = 'LegacyRemoteDesktopClient'
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
function Get-UninstallRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    $roots.Add('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($sid in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue)) {
        if ($sid.PSChildName -notlike 'S-1-5-21-*') { continue }
        if ($sid.PSChildName -like '*_Classes') { continue }
        $roots.Add("Registry::HKEY_USERS\$($sid.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
    }
    return $roots
}
function Get-LegacyClientState {
    $apps = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
        $_.Name -like $LegacyNamePattern -and
        $_.Name -notlike $WindowsAppNamePattern -and
        $_.Publisher -like $LegacyPublisherPattern
    } | Sort-Object -Property PackageFullName -Unique)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
        $_.DisplayName -like $LegacyNamePattern -and $_.DisplayName -notlike $WindowsAppNamePattern
    })
    $msi = New-Object System.Collections.Generic.List[object]
    foreach ($root in Get-UninstallRoots) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            if ([string]$props.DisplayName -ne $LegacyMsiDisplayName) { continue }
            if ([string]$props.Publisher -notlike $LegacyPublisherPattern) { continue }
            $code = $null
            if ([string]$props.UninstallString -match '\{[0-9A-Fa-f\-]{36}\}') { $code = $Matches[0] }
            elseif ($entry.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $code = $entry.PSChildName }
            $msi.Add([pscustomobject]@{
                ProductCode = $code
                DisplayVersion = [string]$props.DisplayVersion
                Scope = $entry.PSPath
            })
        }
    }
    $windowsApp = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like $WindowsAppNamePattern })
    $versions = New-Object System.Collections.Generic.List[string]
    foreach ($app in $apps) { $versions.Add([string]$app.Version) }
    foreach ($item in $msi) { if ($item.DisplayVersion) { $versions.Add($item.DisplayVersion) } }
    $versionText = 'None'
    if ($versions.Count -gt 0) { $versionText = (@($versions | Sort-Object -Unique) -join '/') }
    [pscustomobject]@{
        Apps = $apps
        Provisioned = $provisioned
        Msi = $msi
        Versions = $versionText
        WindowsAppInstalled = ($windowsApp.Count -gt 0)
        Present = ($apps.Count -gt 0 -or $provisioned.Count -gt 0 -or $msi.Count -gt 0)
    }
}
function Remove-LegacyMsiClient { param([string]$ProductCode)
    if (-not $ProductCode) { return $false }
    $arguments = '/x {0} /qn /norestart' -f $ProductCode
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    Write-IRTLog "MSI uninstall finished with exit code $($process.ExitCode)."
    return @(0, 1605, 3010) -contains $process.ExitCode
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0') { Exit-Script 0 'NotApplicable | WindowsClient=False' }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error | Reason=Use64BitPowerShell' }
    $state = Get-LegacyClientState
    if ($OnlyWhenWindowsAppInstalled -and -not $state.WindowsAppInstalled) {
        Exit-Script 0 'NotApplicable | WindowsApp=NotInstalled; RemovalSkipped=True'
    }
    if (-not $state.Present) { Exit-Script 0 'Healthy | Appx=0; Provisioned=0; Msi=0' }
    if ($DeferWhileRunning) {
        $running = @()
        foreach ($name in $LegacyProcessNames) { $running += @(Get-Process -Name $name -ErrorAction SilentlyContinue) }
        if ($running.Count -gt 0) { Exit-Script 1 'Deferred | Reason=LegacyClientRunning; Retry=NextSchedule' }
    }
    $restartNeeded = $false
    $appxRemoved = 0
    $msiRemoved = 0
    $failed = 0
    if ($RemoveProvisioned) {
        foreach ($item in $state.Provisioned) {
            try {
                $result = Remove-AppxProvisionedPackage -Online -PackageName $item.PackageName -ErrorAction Stop
                if ($result.RestartNeeded) { $restartNeeded = $true }
                Write-IRTLog 'Provisioned entry removed.'
            }
            catch {
                $failed++
                Write-IRTLog ('Provisioned removal failed: {0}' -f $_.Exception.HResult) 'WARN'
            }
        }
    }
    foreach ($app in $state.Apps) {
        try {
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
            $appxRemoved++
            Write-IRTLog 'All-user registration removed.'
        }
        catch {
            $failed++
            Write-IRTLog ('Appx removal failed: {0}' -f $_.Exception.HResult) 'WARN'
        }
    }
    if ($RemoveMsiClient) {
        foreach ($item in $state.Msi) {
            if (Remove-LegacyMsiClient -ProductCode $item.ProductCode) { $msiRemoved++ }
            else {
                $failed++
                Write-IRTLog 'MSI client removal did not complete.' 'WARN'
            }
        }
    }
    $after = Get-LegacyClientState
    $summary = 'AppxRemoved={0}; MsiRemoved={1}; RemainingAppx={2}; RemainingProvisioned={3}; RemainingMsi={4}; RestartNeeded={5}' -f $appxRemoved, $msiRemoved, $after.Apps.Count, $after.Provisioned.Count, $after.Msi.Count, $restartNeeded
    if ($failed -gt 0) { $summary = '{0}; Errors={1}' -f $summary, $failed }
    if ($after.Present) { Exit-Script 1 "Failed | $summary" }
    if ($restartNeeded) { Exit-Script 1 "PendingRestart | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 ('Error | HResult={0}; Reason=RemovalOrVerificationFailed' -f $_.Exception.HResult) }
