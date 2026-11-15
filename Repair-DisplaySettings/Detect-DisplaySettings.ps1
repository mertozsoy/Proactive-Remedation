<#
.SYNOPSIS
  Detection script for Display settings that never load because the Connected Devices Platform services are disabled.

.DESCRIPTION
  Reads the start type of CDPSvc, the CDPUserSvc template and every CDPUserSvc_* per-user instance from the registry and checks the EnableCdp policy. Exits 1 if a start type is not Automatic or the policy blocks the platform, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RequiredStartType = 2
$ServiceNames      = @('CDPSvc', 'CDPUserSvc')
$ServiceKeyRoot    = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$InstancePrefix    = 'CDPUserSvc_'
$PolicyKeyPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$PolicyValueName   = 'EnableCdp'

$PackageName = 'DisplaySettings'
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

function Get-StartType { param([string]$ServiceName)
    $path = Join-Path $ServiceKeyRoot $ServiceName
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $path -Name Start -ErrorAction SilentlyContinue
    if ($null -eq $item) { return -1 }
    return [int]$item.Start
}

function Get-CdpInstanceName {
    @(Get-ChildItem -LiteralPath $ServiceKeyRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName.StartsWith($InstancePrefix) } |
        ForEach-Object { $_.PSChildName })
}

function Get-CdpPolicyState {
    $item = Get-ItemProperty -LiteralPath $PolicyKeyPath -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'NotConfigured' }
    if ($null -eq $item.PSObject.Properties[$PolicyValueName]) { return 'NotConfigured' }
    if ([int]$item.PSObject.Properties[$PolicyValueName].Value -eq 0) { return 'Disallowed' }
    return 'Allowed'
}

try {
    $missing = 0
    $serviceDrift = @()
    foreach ($name in $ServiceNames) {
        $start = Get-StartType -ServiceName $name
        if ($null -eq $start) { $missing++; continue }
        if ($start -ne $RequiredStartType) { $serviceDrift += ('{0}={1}' -f $name, $start) }
    }
    if ($missing -eq $ServiceNames.Count) { Exit-Script 0 'NotApplicable | Reason=NoCdpService' }

    $instances = @(Get-CdpInstanceName)
    $instanceDrift = 0
    foreach ($instance in $instances) {
        $start = Get-StartType -ServiceName $instance
        if ($start -ne $RequiredStartType) { $instanceDrift++ }
    }

    $policy = Get-CdpPolicyState
    $details = @()
    if ($serviceDrift.Count -gt 0) { $details += ('Start=' + ($serviceDrift -join ',')) }
    if ($instanceDrift -gt 0) { $details += "InstanceDrift=$instanceDrift" }
    if ($policy -eq 'Disallowed') { $details += 'Policy=Disallowed' }

    if ($details.Count -eq 0) {
        Exit-Script 0 "Healthy | Services=Automatic; Instances=$($instances.Count); Policy=$policy"
    }

    Exit-Script 1 ('Drift | ' + ($details -join '; '))
}
catch { Exit-Script 1 "Error: Failed | Operation=Detect; HResult=$($_.Exception.HResult)" }
