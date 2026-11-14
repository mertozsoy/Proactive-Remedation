<#
.SYNOPSIS
  Remediation script that re-enables App Installer on devices hardened with EnableAppInstaller=0.

.DESCRIPTION
  Backs up the App Installer policy key and removes the EnableAppInstaller value so the policy returns to Not configured. Exits 0 if the value is gone or set to 1, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$PolicyKeyPath    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller'
$PolicyValue      = 'EnableAppInstaller'
$CheckPackage     = $true
$EnableRemediation = $true
$RemovePolicyValue = $true

$PackageName = 'AppInstaller'
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

function Backup-PolicyKey {
    $backupDir = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
    }
    $stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $backupDir "AppInstallerPolicy-$stamp.reg"
    & "$env:SystemRoot\System32\reg.exe" export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppInstaller' $backupFile /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Registry backup failed with exit code $LASTEXITCODE" }
    Write-IRTLog "Policy key exported to $backupFile"
    return $backupFile
}

try {
    $value = Get-PolicyValue

    if ($null -eq $value) {
        Exit-Script 0 "Healthy | EnableAppInstaller=NotConfigured; AppInstaller=$(Get-AppInstallerVersion)"
    }
    if ($value -eq '1') {
        Exit-Script 0 "Healthy | EnableAppInstaller=1; AppInstaller=$(Get-AppInstallerVersion)"
    }
    if ($value -ne '0') {
        Exit-Script 0 "ReportOnly | EnableAppInstaller=$value; AppInstaller=$(Get-AppInstallerVersion)"
    }
    if (-not $EnableRemediation) {
        Exit-Script 0 "ReportOnly | EnableAppInstaller=0; AppInstaller=$(Get-AppInstallerVersion)"
    }

    $backupFile = Backup-PolicyKey

    if ($RemovePolicyValue) {
        Remove-ItemProperty -LiteralPath $PolicyKeyPath -Name $PolicyValue -Force -ErrorAction Stop
        Write-IRTLog "Removed policy value $PolicyValue"
    }
    else {
        $kind = (Get-Item -LiteralPath $PolicyKeyPath -ErrorAction Stop).GetValueKind($PolicyValue)
        if ($kind -eq 'String') {
            Set-ItemProperty -LiteralPath $PolicyKeyPath -Name $PolicyValue -Value '1' -Type String -Force -ErrorAction Stop
        }
        else {
            Set-ItemProperty -LiteralPath $PolicyKeyPath -Name $PolicyValue -Value 1 -Type DWord -Force -ErrorAction Stop
        }
        Write-IRTLog "Set policy value $PolicyValue to 1"
    }

    $after   = Get-PolicyValue
    $version = Get-AppInstallerVersion

    if ($null -eq $after) {
        Exit-Script 0 "Fixed | EnableAppInstaller=NotConfigured; AppInstaller=$version; Backup=$backupFile"
    }
    if ($after -eq '1') {
        Exit-Script 0 "Fixed | EnableAppInstaller=1; AppInstaller=$version; Backup=$backupFile"
    }
    Exit-Script 1 "Failed | EnableAppInstaller=$after; AppInstaller=$version; Backup=$backupFile"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
