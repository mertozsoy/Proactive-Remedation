<#
.SYNOPSIS
  Detection script for stale third-party antivirus registrations in Windows Security Center.

.DESCRIPTION
  Lists the antivirus products registered with Windows Security Center, checks the recorded product executable on disk and reports registrations that point to a missing file. Also reports the Defender running mode and the passive mode policy. Exits 1 if a stale registration is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExcludeNamePattern = 'Microsoft Defender|Windows Defender'
$ExcludePathPattern = '\\Windows Defender\\|\\Microsoft Defender\\'
$KnownStaleNames    = @()
$MaxNamesInOutput   = 5

$PackageName = 'StaleAvRegistration'
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

$PassivePolicyKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection'
$PassivePolicyName = 'ForceDefenderPassiveMode'

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
        Exit-Script 0 "PolicyManaged | ForceDefenderPassiveMode=1; Registered=$($registered.Count); Stale=$($stale.Count)"
    }
    if ($stale.Count -eq 0) {
        Exit-Script 0 "Healthy | Registered=$($registered.Count); Stale=0; DefenderMode=$($defender.Mode); Rtp=$($defender.Rtp)"
    }
    Exit-Script 1 "StaleAv | Registered=$($registered.Count); Stale=$($stale.Count); Names=$names; DefenderMode=$($defender.Mode); Rtp=$($defender.Rtp)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
