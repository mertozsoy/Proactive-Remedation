<#
.SYNOPSIS
  Detection script for mDNS network blocking.

.DESCRIPTION
  Checks four UDP 5353 block rules in the effective firewall policy and all firewall profiles.
  Exits 1 for missing protection or an unavailable prerequisite, 0 when configured.
  Checks configuration rather than probing network traffic or stopping a responder process.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MdnsPort = '5353'
$RuleGroup = 'IRT mDNS isolation'

$PackageName = 'MdnsResponder'
$Phase = 'Detect'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Test-MdnsRule { param($Rule, [string]$Direction, [string]$Side)
    if ($null -eq $Rule) { return $false }
    if ($Rule.Group -ne $RuleGroup -or $Rule.Enabled -ne 'True' -or
        $Rule.Action -ne 'Block' -or $Rule.Direction -ne $Direction -or
        $Rule.Profile -ne 'Any' -or $Rule.PrimaryStatus -ne 'OK') { return $false }
    $port = $Rule | Get-NetFirewallPortFilter -ErrorAction Stop
    $address = $Rule | Get-NetFirewallAddressFilter -ErrorAction Stop
    $app = $Rule | Get-NetFirewallApplicationFilter -ErrorAction Stop
    $service = $Rule | Get-NetFirewallServiceFilter -ErrorAction Stop
    $interface = $Rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop
    $interfaceType = $Rule | Get-NetFirewallInterfaceTypeFilter -ErrorAction Stop
    $localPort = 'Any'
    $remotePort = 'Any'
    if ($Side -eq 'Local') { $localPort = $MdnsPort } else { $remotePort = $MdnsPort }
    return (($port.Protocol -eq 'UDP' -or $port.Protocol -eq '17') -and
        (@($port.LocalPort) -join ',') -eq $localPort -and
        (@($port.RemotePort) -join ',') -eq $remotePort -and
        (@($address.LocalAddress) -join ',') -eq 'Any' -and
        (@($address.RemoteAddress) -join ',') -eq 'Any' -and
        $app.Program -eq 'Any' -and $app.Package -eq 'Any' -and
        $service.Service -eq 'Any' -and
        (@($interface.InterfaceAlias) -join ',') -eq 'Any' -and
        $interfaceType.InterfaceType -eq 'Any')
}

try {
    Import-Module NetSecurity -ErrorAction Stop
    $firewall = Get-Service -Name MpsSvc -ErrorAction Stop
    if ($firewall.Status -ne 'Running') { Exit-Script 1 'Blocked | Reason=FirewallServiceNotRunning; Action=ReviewFirewallPolicy' }
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    if ($profiles.Count -ne 3 -or @($profiles | Where-Object { $_.Enabled -ne 'True' }).Count -gt 0) {
        Exit-Script 1 'Blocked | Reason=FirewallProfileDisabled; Action=ReviewFirewallPolicy'
    }
    if (@($profiles | Where-Object { $_.AllowLocalFirewallRules -eq 'False' }).Count -gt 0) {
        Exit-Script 1 'Blocked | Reason=LocalPolicyMergeDisabled; Action=DeployCentralRules'
    }
    if (@($profiles | Where-Object { @($_.DisabledInterfaceAliases | Where-Object { $_ -and $_ -ne 'NotConfigured' }).Count -gt 0 }).Count -gt 0) {
        Exit-Script 1 'Blocked | Reason=FirewallInterfaceExcluded; Action=ReviewFirewallPolicy'
    }
    $activeRules = @(Get-NetFirewallRule -PolicyStore ActiveStore -TracePolicyStore -ErrorAction Stop)
    $missing = 0
    foreach ($direction in @('Inbound', 'Outbound')) {
        foreach ($side in @('Local', 'Remote')) {
            $name = "IRT-MdnsResponder-$direction-$side"
            $rules = @($activeRules | Where-Object { $_.Name -eq $name })
            if ($rules.Count -ne 1) { $missing++; continue }
            if (-not (Test-MdnsRule -Rule $rules[0] -Direction $direction -Side $side)) { $missing++ }
        }
    }
    if ($missing -gt 0) { Exit-Script 1 "Drift | InvalidRules=$missing; RequiredRules=4; UDP=$MdnsPort" }
    Exit-Script 0 "Healthy | EffectiveRules=4; UDP=$MdnsPort; Profiles=All"
}
catch { Exit-Script 1 "Error: OperationFailed | Type=$($_.Exception.GetType().Name)" }
