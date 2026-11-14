<#
.SYNOPSIS
  Detection script for a disabled App Installer policy that blocks Intune Store app installs.

.DESCRIPTION
  Reads the EnableAppInstaller policy value under HKLM and the installed App Installer package. Exits 1 if the policy value is 0, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyKeyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller'
$PolicyValue   = 'EnableAppInstaller'
$CheckPackage  = $true

$PackageName = 'AppInstaller'
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

function Get-PolicyValue {
    if (-not (Test-Path -LiteralPath $PolicyKeyPath)) { return $null }
    $item = Get-ItemProperty -LiteralPath $PolicyKeyPath -Name $PolicyValue -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $raw = $item.$PolicyValue
    if ($null -eq $raw) { return $null }
    return [string]$raw
}

function Get-AppInstallerVersion {
    if (-not $CheckPackage) { return 'Skipped' }
    try {
        $pkg = Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop |
            Sort-Object -Property Version -Descending | Select-Object -First 1
        if ($null -eq $pkg) { return 'NotInstalled' }
        return [string]$pkg.Version
    }
    catch { return 'Unknown' }
}

try {
    $value   = Get-PolicyValue
    $version = Get-AppInstallerVersion

    if ($null -eq $value) {
        Exit-Script 0 "Healthy | EnableAppInstaller=NotConfigured; AppInstaller=$version"
    }
    if ($value -eq '0') {
        Exit-Script 1 "Drift | EnableAppInstaller=0; AppInstaller=$version; Impact=Store apps fail with 0x87D300CA"
    }
    if ($value -eq '1') {
        Exit-Script 0 "Healthy | EnableAppInstaller=1; AppInstaller=$version"
    }
    Exit-Script 0 "Healthy | EnableAppInstaller=$value; AppInstaller=$version"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
