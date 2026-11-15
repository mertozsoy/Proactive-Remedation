<#
.SYNOPSIS
  Remediation script for http and https protocol associations that point to a missing application.

.DESCRIPTION
  Re-registers the Microsoft Edge package for the signed-in user when its protocol registration is missing. Optionally removes a broken per-user UserChoice entry after backing up the key so Windows can rebuild the association. Refreshes the shell with SHChangeNotify. Exits 0 only when every association resolves to a working handler or has no override left.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$Protocols = @('https', 'http')
$ResetInvalidUserChoice = $false
$RefreshShell = $true

$PackageName = 'HttpsProtocolAssociation'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
$BackupDir   = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup\HttpsProtocolAssociation'

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null }
        Add-Content -LiteralPath $LogFile -Value ('{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function ConvertTo-ExecutablePath {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    if ($expanded.StartsWith('"')) {
        $end = $expanded.IndexOf('"', 1)
        if ($end -gt 1) { return $expanded.Substring(1, $end - 1) }
        return ''
    }
    $match = [regex]::Match($expanded, '^(.*?\.exe)(\s|$)')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ($expanded -split '\s+')[0]
}

function Get-UserChoicePath {
    param([string]$Protocol)
    return ('HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\{0}\UserChoice' -f $Protocol)
}

function Get-ProtocolAssociation {
    param([string]$Protocol)
    $association = [pscustomobject]@{
        Protocol   = $Protocol
        ProgId     = ''
        Command    = ''
        Executable = ''
        State      = 'Missing'
    }
    $keyPath = Get-UserChoicePath -Protocol $Protocol
    if (-not (Test-Path -LiteralPath $keyPath)) { return $association }
    $values = Get-ItemProperty -LiteralPath $keyPath -ErrorAction Stop
    $progId = [string]$values.ProgId
    if ([string]::IsNullOrWhiteSpace($progId)) { $association.State = 'NoProgId'; return $association }
    $association.ProgId = $progId
    if ([string]::IsNullOrWhiteSpace([string]$values.Hash)) { $association.State = 'NoHash'; return $association }
    $commandKey = 'Registry::HKEY_CLASSES_ROOT\{0}\shell\open\command' -f $progId
    $command = [string](Get-ItemProperty -LiteralPath $commandKey -ErrorAction SilentlyContinue).'(default)'
    if ([string]::IsNullOrWhiteSpace($command)) { $association.State = 'NoCommand'; return $association }
    $association.Command = $command
    $executable = ConvertTo-ExecutablePath -Command $command
    $association.Executable = $executable
    if ([string]::IsNullOrWhiteSpace($executable) -or -not (Test-Path -LiteralPath $executable)) {
        $association.State = 'MissingApp'
        return $association
    }
    $association.State = 'Valid'
    return $association
}

function Format-Summary {
    param($Associations, [string]$EdgeState)
    $pairs = @()
    foreach ($association in $Associations) { $pairs += ('{0}={1}' -f $association.Protocol, $association.State) }
    return ('{0}; Edge={1}' -f ($pairs -join '; '), $EdgeState)
}

function Find-EdgeManifest {
    param([switch]$AllUsers)
    $packages = @()
    try {
        if ($AllUsers) {
            $packages = @(Get-AppxPackage -Name 'Microsoft.MicrosoftEdge.Stable*' -AllUsers -ErrorAction Stop)
        } else {
            $packages = @(Get-AppxPackage -Name 'Microsoft.MicrosoftEdge.Stable*' -ErrorAction Stop)
        }
    } catch {
        return ''
    }
    foreach ($package in $packages) {
        if ([string]::IsNullOrWhiteSpace([string]$package.InstallLocation)) { continue }
        $candidate = Join-Path ([string]$package.InstallLocation) 'AppxManifest.xml'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ''
}

function Get-EdgePackageState {
    $executables = @()
    $appPath = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -ErrorAction SilentlyContinue).'(default)'
    if (-not [string]::IsNullOrWhiteSpace([string]$appPath)) { $executables += [string]$appPath }
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) { $executables += (Join-Path $programFilesX86 'Microsoft\Edge\Application\msedge.exe') }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) { $executables += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe') }
    $installed = $false
    foreach ($candidate in $executables) {
        if (Test-Path -LiteralPath $candidate) { $installed = $true; break }
    }
    $manifest = Find-EdgeManifest
    $registered = -not [string]::IsNullOrWhiteSpace($manifest)
    if (-not $registered) {
        $machineManifest = Find-EdgeManifest -AllUsers
        if (-not [string]::IsNullOrWhiteSpace($machineManifest)) { $manifest = $machineManifest }
    }
    if ([string]::IsNullOrWhiteSpace($manifest)) {
        $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
        if (Test-Path -LiteralPath $windowsApps) {
            try {
                $folders = @(Get-ChildItem -LiteralPath $windowsApps -Directory -Filter 'Microsoft.MicrosoftEdge.Stable_*' -ErrorAction Stop | Select-Object -First 1)
                if ($folders.Count -gt 0) {
                    $candidate = Join-Path $folders[0].FullName 'AppxManifest.xml'
                    if (Test-Path -LiteralPath $candidate) { $manifest = $candidate }
                }
            } catch { }
        }
    }
    $state = 'NotInstalled'
    if ($installed) { $state = 'NotRegistered' }
    if ($registered) { $state = 'Registered' }
    [pscustomobject]@{
        State        = $state
        Installed    = $installed
        Registered   = $registered
        ManifestPath = $manifest
    }
}

function Register-EdgePackage {
    param([string]$ManifestPath)
    Add-AppxPackage -Path $ManifestPath -Register -DisableDevelopmentMode -ErrorAction Stop
    Write-IRTLog 'Edge package registered for the current user'
}

function Backup-ProtocolKey {
    param([string]$Protocol)
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force -ErrorAction Stop | Out-Null }
    $destination = Join-Path $BackupDir ('{0}_{1}_UserChoice.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), $Protocol)
    $keyPath = 'HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\{0}\UserChoice' -f $Protocol
    & reg.exe export "$keyPath" "$destination" /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destination)) { throw ('Registry backup failed for {0}' -f $Protocol) }
    Write-IRTLog ('UserChoice backup written for {0}' -f $Protocol)
}

function Invoke-ShellRefresh {
    if (-not ('IRT.Shell32' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace IRT {
    public static class Shell32 {
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
    }
}
'@
    }
    [IRT.Shell32]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
}

try {
    $ErrorActionPreference = 'Stop'
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem -or [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        Exit-Script 0 'NotApplicable | Context=NonUserSession'
    }

    $associations = @()
    foreach ($protocol in $Protocols) { $associations += Get-ProtocolAssociation -Protocol $protocol }
    $edge = Get-EdgePackageState
    $broken = @($associations | Where-Object { $_.State -ne 'Valid' -and $_.State -ne 'Missing' })
    if ($broken.Count -eq 0) {
        Exit-Script 0 ('Healthy | {0}; Action=None' -f (Format-Summary -Associations $associations -EdgeState $edge.State))
    }
    Write-IRTLog ('Broken associations found: {0}' -f ($broken.Protocol -join ','))

    $registration = 'None'
    if (-not $edge.Registered) {
        if ([string]::IsNullOrWhiteSpace($edge.ManifestPath)) {
            Exit-Script 1 ('Failed | {0}; Reason=EdgePackageUnavailable; Action=None' -f (Format-Summary -Associations $associations -EdgeState $edge.State))
        }
        try {
            Register-EdgePackage -ManifestPath $edge.ManifestPath
            $registration = 'RegisterEdge'
        } catch {
            Exit-Script 1 ('Error: EdgeRegistrationFailed | HResult={0}' -f $_.Exception.HResult)
        }
        if ($RefreshShell) { Invoke-ShellRefresh }
        $edge = Get-EdgePackageState
        $associations = @()
        foreach ($protocol in $Protocols) { $associations += Get-ProtocolAssociation -Protocol $protocol }
        $broken = @($associations | Where-Object { $_.State -ne 'Valid' -and $_.State -ne 'Missing' })
    }

    $resetCount = 0
    $resetFailed = 0
    $backupState = 'None'
    if ($broken.Count -gt 0 -and $ResetInvalidUserChoice) {
        foreach ($item in $broken) {
            try {
                Backup-ProtocolKey -Protocol $item.Protocol
                $backupState = 'Saved'
                Remove-Item -LiteralPath (Get-UserChoicePath -Protocol $item.Protocol) -Recurse -Force -ErrorAction Stop
                $resetCount++
                Write-IRTLog ('Invalid UserChoice removed for {0}' -f $item.Protocol)
            } catch {
                $resetFailed++
                Write-IRTLog ('UserChoice reset failed for {0}' -f $item.Protocol) 'WARN'
            }
        }
        if ($RefreshShell -and $resetCount -gt 0) { Invoke-ShellRefresh }
        $associations = @()
        foreach ($protocol in $Protocols) { $associations += Get-ProtocolAssociation -Protocol $protocol }
    }

    $actions = @()
    if ($registration -ne 'None') { $actions += $registration }
    if ($resetCount -gt 0) { $actions += 'ResetUserChoice' }
    if ($actions.Count -eq 0) { $actions = @('None') }
    $remaining = @($associations | Where-Object { $_.State -ne 'Valid' -and $_.State -ne 'Missing' })
    $summary = '{0}; Action={1}; Backup={2}' -f (Format-Summary -Associations $associations -EdgeState $edge.State), ($actions -join ','), $backupState
    if ($remaining.Count -eq 0) { Exit-Script 0 "Fixed | $summary" }
    if ($resetFailed -gt 0) { Exit-Script 1 "Failed | $summary; Reason=UserChoiceResetFailed" }
    if (-not $ResetInvalidUserChoice) { Exit-Script 1 "Failed | $summary; Reason=UserChoiceResetDisabled" }
    Exit-Script 1 "Failed | $summary; Reason=AssociationStillBroken"
} catch { Exit-Script 1 ('Error: RemediationFailed | HResult={0}' -f $_.Exception.HResult) }
