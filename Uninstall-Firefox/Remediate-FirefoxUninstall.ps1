<#
.SYNOPSIS
    Firefox Uninstall Remediation Script for Intune Proactive Remediation

.DESCRIPTION
    This script silently uninstalls Mozilla Firefox by running the Enterprise App Catalog
    uninstall command with elevated/SYSTEM context:
    "%ProgramFiles%\Mozilla Firefox\uninstall\helper.exe" -ms

    Intune Proactive Remediation must be configured as:
    - Run this script using the logged-on credentials: No
    - Run script in 64-bit PowerShell: Yes

    Returns exit code 0 if uninstall successful or Firefox not present,
    returns exit code 1 if uninstall failed.

.NOTES
    Version: 2.0
    Intune Proactive Remediation - Remediation Script
    Uninstall command source: Enterprise App Catalog
    Command: "%ProgramFiles%\Mozilla Firefox\uninstall\helper.exe" -ms
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] $Message"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-FirefoxInstalled {
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $uninstallPaths) {
        $found = Get-ChildItem -Path $path -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue } |
            Where-Object { $_.DisplayName -like "*Mozilla Firefox*" }

        if ($found) { return $true }
    }

    return (Test-Path -Path "$env:ProgramFiles\Mozilla Firefox\uninstall\helper.exe")
}

Write-Log "=========================================="
Write-Log "Firefox Uninstall Remediation Started"
Write-Log "=========================================="
Write-Log "Running as user: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Is administrator/elevated: $(Test-IsAdministrator)"

if (-not (Test-IsAdministrator)) {
    if ([Environment]::UserInteractive -and $PSCommandPath) {
        Write-Log "Script is not elevated. Relaunching PowerShell as administrator."
        $powerShellPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
        $process = Start-Process -FilePath $powerShellPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        Write-Log "Elevated PowerShell process exited with code: $($process.ExitCode)"
        exit $process.ExitCode
    }

    Write-Log "ERROR: Script is not running elevated. In Intune, set 'Run this script using the logged-on credentials' to 'No'."
    exit 1
}

# If Intune runs the script in 32-bit PowerShell, relaunch in 64-bit PowerShell.
if ($env:PROCESSOR_ARCHITEW6432 -and (Test-Path -Path "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe")) {
    Write-Log "32-bit PowerShell detected. Relaunching in 64-bit PowerShell."
    $sysNativePowerShell = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    $process = Start-Process -FilePath $sysNativePowerShell -ArgumentList $arguments -Wait -PassThru
    Write-Log "64-bit PowerShell process exited with code: $($process.ExitCode)"
    exit $process.ExitCode
}

if (-not (Test-FirefoxInstalled)) {
    Write-Log "Firefox not found. No action needed."
    Write-Log "Remediation completed successfully (already compliant)."
    exit 0
}

$uninstallExe = "$env:ProgramFiles\Mozilla Firefox\uninstall\helper.exe"
$uninstallArgs = "-ms"

if (-not (Test-Path -Path $uninstallExe)) {
    Write-Log "ERROR: Firefox detected but uninstaller was not found: $uninstallExe"
    exit 1
}

Write-Log "Firefox detected."
Write-Log "Executing Enterprise App Catalog uninstall command silently: `"$uninstallExe`" $uninstallArgs"

Write-Log "Closing running Firefox processes."
Get-Process -Name "firefox" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Log "Stopping process: $($_.ProcessName) PID: $($_.Id)"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 3

try {
    $process = Start-Process -FilePath $uninstallExe -ArgumentList $uninstallArgs -Wait -NoNewWindow -PassThru -ErrorAction Stop
    Write-Log "Firefox helper.exe exited with code: $($process.ExitCode)"
}
catch {
    Write-Log "ERROR: Failed to start Firefox uninstaller: $($_.Exception.Message)"
    exit 1
}

Start-Sleep -Seconds 15

if (Test-FirefoxInstalled) {
    Write-Log "FAILED: Firefox still appears to be installed after uninstall attempt."
    exit 1
}

Write-Log "SUCCESS: Firefox has been successfully uninstalled."
Write-Log "=========================================="
Write-Log "Firefox Uninstall Remediation Completed"
Write-Log "=========================================="
exit 0
