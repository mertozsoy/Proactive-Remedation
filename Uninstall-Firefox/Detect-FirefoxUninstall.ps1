<#
.SYNOPSIS
    Firefox Uninstall Detection Script for Intune Proactive Remediation

.DESCRIPTION
    This script detects if Mozilla Firefox is installed on the device.
    Returns exit code 1 if Firefox is found (remediation required),
    returns exit code 0 if Firefox is not found (compliant).
    Checks registry and Program Files path for Mozilla Firefox.

.NOTES
    Version: 1.2
    Intune Proactive Remediation - Detection Script
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] $Message"
}

Write-Log "=========================================="
Write-Log "Firefox Uninstall Detection Started"
Write-Log "=========================================="

# Check for Firefox in registry uninstall keys (both 64-bit and 32-bit)
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$firefoxFound = $false
$productCode = $null
$displayName = $null

foreach ($path in $uninstallPaths) {
    $keys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
    foreach ($key in $keys) {
        $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($props.DisplayName -like "*Mozilla Firefox*") {
            $firefoxFound = $true
            $productCode = $key.PSChildName
            $displayName = $props.DisplayName
            break
        }
    }
    if ($firefoxFound) { break }
}

# Also check Program Files for Firefox installation (fallback)
$firefoxPaths = @(
    "${env:ProgramFiles}\Mozilla Firefox",
    "${env:ProgramFiles(x86)}\Mozilla Firefox"
)

foreach ($ffPath in $firefoxPaths) {
    if (Test-Path -Path "$ffPath\uninstall\helper.exe") {
        $firefoxFound = $true
        break
    }
}

if ($firefoxFound) {
    Write-Log "DETECTED: Mozilla Firefox installation found."
    if ($displayName) { Write-Log "  Name: $displayName" }
    if ($productCode) { Write-Log "  MSI ProductCode: $productCode" }
    Write-Log "=========================================="
    exit 1
}
else {
    Write-Log "COMPLIANT: Mozilla Firefox not installed."
    Write-Log "=========================================="
    exit 0
}
