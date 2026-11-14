<#
.SYNOPSIS
  Detection script for Windows Defender Firewall profiles that are turned off.

.DESCRIPTION
  Reads the effective state of the domain, private and public firewall profiles, the EnableFirewall policy values under HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall and the state of the MpsSvc service. Exits 1 if a profile is off or the service cannot start, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProfileNames   = @('Domain', 'Private', 'Public')
$PolicyRoot     = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall'
$PolicyKeyNames = @{ Domain = 'DomainProfile'; Private = 'PrivateProfile'; Public = 'PublicProfile' }
$ServiceName    = 'MpsSvc'

$PackageName = 'FirewallState'
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

function Get-FirewallServiceState {
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
    if ($null -eq $service) { return 'Missing' }
    if ($service.StartMode -eq 'Disabled') { return 'Disabled' }
    if ($service.State -ne 'Running') { return [string]$service.State }
    'Running'
}

function Get-FirewallState {
    $profileObjects = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    foreach ($name in $ProfileNames) {
        $profileItem = $profileObjects | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        $enabled = 'Unknown'
        if ($profileItem) { $enabled = [string]$profileItem.Enabled }
        if ($enabled -notin @('True', 'False')) { throw "Profile state unavailable: $name" }

        $key = Join-Path $PolicyRoot $PolicyKeyNames[$name]
        $policyValue = $null
        if (Test-Path -LiteralPath $key) {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            if ($null -ne $item.EnableFirewall) { $policyValue = [int]$item.EnableFirewall }
        }

        $source = 'Unspecified'
        if ($null -ne $policyValue -and $policyValue -eq 0) { $source = 'Policy' }

        [pscustomobject]@{
            Name        = $name
            Enabled     = $enabled
            Off         = ($enabled -eq 'False')
            Source      = $source
            PolicyKey   = $key
            PolicyValue = $policyValue
        }
    }
}

function Format-FirewallState {
    param($State)
    (@($State | ForEach-Object {
        if ($_.Off) { '{0}=Off({1})' -f $_.Name, $_.Source } else { '{0}={1}' -f $_.Name, $_.Enabled }
    }) -join '; ')
}

try {
    $serviceState = Get-FirewallServiceState
    if ($serviceState -ne 'Running') {
        Exit-Script 1 "Drift | Profiles=NotQueried; Service=$serviceState"
    }
    $states       = @(Get-FirewallState)
    $summary      = Format-FirewallState -State $states

    if (@($states | Where-Object { $_.Off }).Count -gt 0) {
        Exit-Script 1 "Drift | $summary; Service=$serviceState"
    }
    Exit-Script 0 "Healthy | $summary; Service=$serviceState"
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
