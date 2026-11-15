<#
.SYNOPSIS
  Remediation script for mDNS network blocking.

.DESCRIPTION
  Creates or repairs four owned UDP 5353 block rules in the local firewall store.
  Refuses to change centrally managed rules or firewall profile settings.
  Verifies effective rules after the change. Exits 0 when configured, otherwise 1.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MdnsPort = '5353'
$RuleGroup = 'IRT mDNS isolation'

$PackageName = 'MdnsResponder'
$Phase = 'Remediate'
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
    $localRules = @(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop)
    $expected = @()
    foreach ($direction in @('Inbound', 'Outbound')) {
        foreach ($side in @('Local', 'Remote')) {
            $name = "IRT-MdnsResponder-$direction-$side"
            $expected += [pscustomobject]@{ Name = $name; Direction = $direction; Side = $side }
            $collision = @($activeRules | Where-Object { $_.Name -eq $name -and $_.PolicyStoreSourceType -ne 'Local' })
            $foreign = @($localRules | Where-Object { $_.Name -eq $name -and $_.Group -ne $RuleGroup })
            if ($collision.Count -gt 0 -or $foreign.Count -gt 0) {
                Exit-Script 1 'Blocked | Reason=RuleOwnershipConflict; Action=ReviewCentralRules'
            }
        }
    }
    $changed = 0
    foreach ($item in $expected) {
        $existing = @($localRules | Where-Object { $_.Name -eq $item.Name })
        if ($existing.Count -eq 1 -and (Test-MdnsRule -Rule $existing[0] -Direction $item.Direction -Side $item.Side)) { continue }
        foreach ($rule in $existing) {
            $rule | Remove-NetFirewallRule -ErrorAction Stop
        }
        $parameters = @{
            Name = $item.Name
            DisplayName = $item.Name
            Group = $RuleGroup
            Description = 'Block mDNS UDP traffic. Managed by IRT MdnsResponder.'
            PolicyStore = 'PersistentStore'
            Direction = $item.Direction
            Action = 'Block'
            Enabled = 'True'
            Profile = 'Any'
            Protocol = 'UDP'
            LocalPort = 'Any'
            RemotePort = 'Any'
            LocalAddress = 'Any'
            RemoteAddress = 'Any'
            Program = 'Any'
            Service = 'Any'
            InterfaceAlias = 'Any'
            InterfaceType = 'Any'
            ErrorAction = 'Stop'
        }
        if ($item.Side -eq 'Local') { $parameters.LocalPort = $MdnsPort } else { $parameters.RemotePort = $MdnsPort }
        New-NetFirewallRule @parameters | Out-Null
        $changed++
        Write-IRTLog "RuleUpdated | Name=$($item.Name)"
    }
    $activeRules = @(Get-NetFirewallRule -PolicyStore ActiveStore -TracePolicyStore -ErrorAction Stop)
    foreach ($item in $expected) {
        $rules = @($activeRules | Where-Object { $_.Name -eq $item.Name })
        if ($rules.Count -ne 1) { Exit-Script 1 'Failed | Reason=EffectiveRuleMissing; Action=ReviewFirewallPolicy' }
        if (-not (Test-MdnsRule -Rule $rules[0] -Direction $item.Direction -Side $item.Side)) {
            Exit-Script 1 'Failed | Reason=EffectiveRuleInvalid; Action=ReviewFirewallPolicy'
        }
    }
    Exit-Script 0 "Fixed | ChangedRules=$changed; EffectiveRules=4; UDP=$MdnsPort; Profiles=All"
}
catch { Exit-Script 1 "Error: OperationFailed | Type=$($_.Exception.GetType().Name)" }
