<#
.SYNOPSIS
  Detection script for the Microsoft Update Health Tools state on Windows clients.

.DESCRIPTION
  Reads the OS build and checks the Microsoft Update Health Service, the uninstall entry and the install folder. Exits 1 when the tools are missing on builds earlier than 24H2 or still installed on 24H2 and later, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$Build24H2          = 26100
$ServiceName        = 'uhssvc'
$ProductNamePattern = 'Microsoft Update Health Tools*'
$InstallFolder      = Join-Path $env:ProgramFiles 'Microsoft Update Health Tools'

$PackageName = 'UpdateHealthTools'
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

$VersionKey    = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$ProductKey    = 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions'
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Get-HealthToolsEntry {
    $entries = @()
    foreach ($root in $UninstallKeys) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            $name = [string]$props.DisplayName
            if ($name -notlike $ProductNamePattern) { continue }
            $entries += [pscustomobject]@{ KeyName = $key.PSChildName; Name = $name }
        }
    }
    @($entries)
}

function Get-HealthToolsState {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $entries = @(Get-HealthToolsEntry)
    [pscustomobject]@{
        Service   = [bool]$service
        Uninstall = ($entries.Count -gt 0)
        Folder    = (Test-Path -LiteralPath $InstallFolder)
    }
}

function Get-OSBuild {
    $raw   = [string](Get-ItemProperty -LiteralPath $VersionKey -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue).CurrentBuildNumber
    $build = [int]$raw
    if ($build -lt 10240) { throw "OS build number not readable: $raw" }
    $build
}

try {
    $productType = [string](Get-ItemProperty -LiteralPath $ProductKey -Name 'ProductType' -ErrorAction SilentlyContinue).ProductType
    if ($productType -and $productType -ne 'WinNT') { Exit-Script 0 "NotApplicable | ProductType=$productType" }

    $build = Get-OSBuild
    $state = Get-HealthToolsState
    $present = $false
    if ($state.Service -or $state.Uninstall -or $state.Folder) { $present = $true }

    if ($build -ge $Build24H2) {
        if (-not $present) { Exit-Script 0 "Healthy | Build=$build; HealthTools=Absent" }
        Exit-Script 1 "Leftover | Build=$build; Service=$($state.Service); UninstallEntry=$($state.Uninstall); Folder=$($state.Folder)"
    }

    if ($present) { Exit-Script 0 "Healthy | Build=$build; HealthTools=Present; Service=$($state.Service)" }
    Exit-Script 1 "Missing | Build=$build; HealthTools=Absent; Expected=KB4023057"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
