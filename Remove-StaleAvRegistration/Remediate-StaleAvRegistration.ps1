<#
.SYNOPSIS
  Remediation script that removes stale third-party antivirus registrations from Windows Security Center.

.DESCRIPTION
  Finds antivirus registrations whose recorded product executable is missing and removes the matching Security Center provider key after a registry backup. The removal is off by default and only runs when $RemoveStaleRegistration is set to $true. Exits 0 when nothing is left to fix, 1 when the cleanup fails.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RemoveStaleRegistration = $false
$ExcludeNamePattern      = 'Microsoft Defender|Windows Defender'
$ExcludePathPattern      = '\\Windows Defender\\|\\Microsoft Defender\\'
$KnownStaleNames         = @()
$MaxNamesInOutput        = 5

$PackageName = 'StaleAvRegistration'
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

$PassivePolicyKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection'
$PassivePolicyName = 'ForceDefenderPassiveMode'
$ProviderRoot      = 'HKLM:\SOFTWARE\Microsoft\Security Center\Provider\Av'
$BackupRoot        = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

function Get-DefenderState {
    $result = [pscustomobject]@{ Mode = 'Unknown'; Rtp = 'Unknown' }
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        if ($status.AMRunningMode) { $result.Mode = [string]$status.AMRunningMode }
        $result.Rtp = [string]$status.RealTimeProtectionEnabled
        return $result
    } catch { }
    try {
        $status = Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' -ClassName MSFT_MpComputerStatus -ErrorAction Stop
        if ($status.AMRunningMode) { $result.Mode = [string]$status.AMRunningMode }
        $result.Rtp = [string]$status.RealTimeProtectionEnabled
    } catch { }
    $result
}

function Get-AvRegistration {
    $list = @()
    $products = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop
    foreach ($product in $products) {
        $name = [string]$product.displayName
        if (-not $name) { continue }
        if ($name -match $ExcludeNamePattern) { continue }
        $exe = [string]$product.pathToSignedProductExe
        if ($exe -match $ExcludePathPattern) { continue }
        $exists = $false
        if ($exe) {
            try {
                $resolved = [Environment]::ExpandEnvironmentVariables($exe)
                $exists = Test-Path -LiteralPath $resolved -PathType Leaf
            } catch { $exists = $false }
        }
        $list += [pscustomobject]@{
            Name        = $name
            ProductGuid = [string]$product.instanceGuid
            Path        = $exe
            Exists      = $exists
        }
    }
    $list
}

function Get-StaleRegistration {
    param($Registration)
    $stale = @()
    foreach ($item in $Registration) {
        if ($item.Exists) { continue }
        if (-not $item.Path -and ($KnownStaleNames -notcontains $item.Name)) { continue }
        $stale += $item
    }
    $stale
}

function Get-ProviderKey {
    param([string]$Name, [string]$ProductGuid)
    $found = @()
    if (-not (Test-Path -LiteralPath $ProviderRoot)) { return $found }
    $guid = $ProductGuid.Trim('{', '}')
    foreach ($key in Get-ChildItem -LiteralPath $ProviderRoot -ErrorAction SilentlyContinue) {
        $displayName = [string](Get-ItemProperty -LiteralPath $key.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
        if ($displayName -and $displayName -eq $Name) { $found += $key; continue }
        if ($guid -and $key.PSChildName.Trim('{', '}') -eq $guid) { $found += $key }
    }
    $found
}

function Save-ProviderBackup {
    $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    $file = Join-Path $BackupRoot ('SecurityCenter-ProviderAv-{0}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $output = & reg.exe export 'HKLM\SOFTWARE\Microsoft\Security Center\Provider\Av' $file /y 2>&1
    if ($LASTEXITCODE -ne 0) { throw "reg export failed with exit code $LASTEXITCODE ($($output -join ' '))" }
    $file
}

try {
    $defender = Get-DefenderState

    try { $registered = @(Get-AvRegistration) } catch { Exit-Script 0 'NotApplicable | Security Center antivirus list unavailable' }

    $stale = @(Get-StaleRegistration -Registration $registered)
    $names = (($stale | Select-Object -ExpandProperty Name -Unique | Select-Object -First $MaxNamesInOutput) -join ' / ')

    $policyValue = 0
    try {
        $policy = Get-ItemProperty -LiteralPath $PassivePolicyKey -Name $PassivePolicyName -ErrorAction SilentlyContinue
        if ($null -ne $policy) { $policyValue = [int]$policy.$PassivePolicyName }
    } catch { }

    if ($policyValue -eq 1) {
        Exit-Script 0 "Skipped | PolicyManaged; ForceDefenderPassiveMode=1; Stale=$($stale.Count)"
    }
    if ($stale.Count -eq 0) {
        Exit-Script 0 "Healthy | Registered=$($registered.Count); Stale=0; DefenderMode=$($defender.Mode)"
    }
    if (-not $RemoveStaleRegistration) {
        Exit-Script 0 "ReportOnly | Stale=$($stale.Count); Names=$names; DefenderMode=$($defender.Mode); Toggle=RemoveStaleRegistration"
    }

    $backupFile = $null
    $removed    = 0
    foreach ($item in $stale) {
        $keys = @(Get-ProviderKey -Name $item.Name -ProductGuid $item.ProductGuid)
        if ($keys.Count -ne 1) {
            Write-IRTLog "Provider key not matched for $($item.Name), matches: $($keys.Count)"
            continue
        }
        if (-not $backupFile) { $backupFile = Save-ProviderBackup }
        Remove-Item -LiteralPath $keys[0].PSPath -Recurse -Force -ErrorAction Stop
        Write-IRTLog "Provider key removed: $($keys[0].PSChildName) $($item.Name)"
        $removed++
    }

    $left = 0
    foreach ($item in $stale) {
        $left += @(Get-ProviderKey -Name $item.Name -ProductGuid $item.ProductGuid).Count
    }

    if ($removed -eq 0) { Exit-Script 1 "Failed | Stale=$($stale.Count); Removed=0; Names=$names" }
    if ($left -gt 0) { Exit-Script 1 "Partial | Removed=$removed; Remaining=$left; Backup=$backupFile" }
    Exit-Script 0 "Fixed | Removed=$removed; Names=$names; DefenderMode=$($defender.Mode); Note=mode updates on next WSC refresh; Backup=$backupFile"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
