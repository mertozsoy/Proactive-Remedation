<#
.SYNOPSIS
  Re-registers Start menu and ShellExperienceHost for the signed-in user.

.DESCRIPTION
  Repairs missing or unhealthy registrations from existing Windows system manifests.
  ForceReregister also repairs registered components for a confirmed user-visible fault.
  Does not close applications, reset user data or change policies. Exits 0 after verified
  registration, 1 if source files are unavailable, registration fails or verification fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ForceReregister = $false

$PackageName = 'StartMenuRegistration'
$Phase = 'Remediate'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-ShellState {
    foreach ($component in @('StartMenuExperienceHost', 'ShellExperienceHost')) {
        $name = "Microsoft.Windows.$component"
        $apps = @(Get-AppxPackage -Name $name -ErrorAction Stop | Where-Object { $_.Name -eq $name -and $_.PublisherId -eq 'cw5n1h2txyewy' })
        $manifests = @()
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $env:windir 'SystemApps') -Directory -Filter "*$component*" -ErrorAction Stop)) {
            $path = Join-Path $directory.FullName 'AppxManifest.xml'
            if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop)) { continue }
            [xml]$manifest = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if ([string]$manifest.Package.Identity.Name -eq $name) { $manifests += $path }
        }
        $state = 'Registered'
        if ($manifests.Count -ne 1) { $state = 'SourceUnavailable' }
        elseif ($apps.Count -eq 0) { $state = 'Missing' }
        elseif ($apps.Count -ne 1 -or [string]$apps[0].Status -ne 'Ok') { $state = 'Unhealthy' }
        [pscustomobject]@{ Component = $component; Name = $name; State = $state; Manifest = ($manifests | Select-Object -First 1) }
    }
}
try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if ($identity.IsSystem -or [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { Exit-Script 0 'NotApplicable | Context=InteractiveUserRequired' }
    if ($principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { Exit-Script 0 'NotApplicable | Context=NonElevatedUserRequired' }
    if ([System.Environment]::OSVersion.Version.Build -lt 18362) { Exit-Script 0 'NotApplicable | OS=Windows1903OrLaterRequired' }
    $states = @(Get-ShellState)
    $repaired = 0
    $failures = 0
    foreach ($item in $states) {
        if ($item.State -eq 'SourceUnavailable') {
            $failures++
            Write-IRTLog "Component=$($item.Component); State=SourceUnavailable; Action=ManualWindowsRepair" 'WARN'
            continue
        }
        if ($item.State -eq 'Registered' -and -not $ForceReregister) { continue }
        try {
            Add-AppxPackage -Path $item.Manifest -Register -DisableDevelopmentMode -ErrorAction Stop | Out-Null
            $repaired++
            Write-IRTLog "Component=$($item.Component); Action=Registered"
        } catch {
            $failures++
            Write-IRTLog ('Component={0}; Action=Failed; HResult={1}; Type={2}' -f $item.Component, $_.Exception.HResult, $_.Exception.GetType().Name) 'ERROR'
        }
    }
    $verified = @(Get-ShellState)
    $summary = ($verified | ForEach-Object { '{0}={1}' -f $_.Component, $_.State }) -join '; '
    if ($failures -gt 0 -or @($verified | Where-Object { $_.State -ne 'Registered' }).Count -gt 0) {
        Exit-Script 1 "Failed | $summary; ReRegistered=$repaired; Errors=$failures"
    }
    if ($repaired -eq 0) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 0 "Fixed | $summary; ReRegistered=$repaired; Validation=RegistrationOnly"
} catch { Exit-Script 1 ('Error: Repair failed | HResult={0}; Type={1}' -f $_.Exception.HResult, $_.Exception.GetType().Name) }
