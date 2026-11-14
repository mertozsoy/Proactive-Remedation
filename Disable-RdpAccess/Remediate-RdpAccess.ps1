<#
.SYNOPSIS
  Remediation script to close Remote Desktop on clients that are not approved for RDP.

.DESCRIPTION
  Sets fDenyTSConnections to 1 and disables enabled inbound firewall rules for port 3389.
  Devices with an approval marker, with a policy owned RDP setting or with remediation
  switched off are left unchanged. Never disconnects sessions or restarts the device.
  Exits 0 after verified success or when inapplicable, 1 if blocked or unsuccessful.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedGroupName    = 'RDP-Approved'
$ApprovedDeviceNames  = @()
$RdpManagedByPolicy   = $false
$EnableRemediation    = $true
$DisableFirewallRules = $true

$PackageName = 'RdpAccess'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

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

$TerminalServerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$PolicyKey         = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$RdpPort           = '3389'

function Test-RdpApproved {
    foreach ($name in $ApprovedDeviceNames) {
        if (-not $name) { continue }
        if ($name -eq $env:COMPUTERNAME) { return $true }
    }
    try {
        $group = Get-LocalGroup -Name $ApprovedGroupName -ErrorAction SilentlyContinue
        if ($null -eq $group) { return $false }
        $members = @(Get-LocalGroupMember -Group $group.Name -ErrorAction Stop)
        return ($members.Count -gt 0)
    }
    catch { return $false }
}

function Get-RdpEnabledState {
    $value = (Get-ItemProperty -LiteralPath $TerminalServerKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
    if ($null -eq $value) { return $null }
    return ([int]$value -eq 0)
}

function Get-RdpPolicyState {
    if ($RdpManagedByPolicy) { return $true }
    $value = (Get-ItemProperty -LiteralPath $PolicyKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
    if ($null -eq $value) { return $false }
    return ([int]$value -eq 0)
}

function Get-RdpFirewallRule {
    $found = @()
    $portFilters = @(Get-NetFirewallPortFilter -ErrorAction Stop)
    foreach ($filter in $portFilters) {
        if ($filter.Protocol -ne 'TCP' -and $filter.Protocol -ne 'UDP') { continue }
        if (@($filter.LocalPort) -notcontains $RdpPort) { continue }
        foreach ($rule in @(Get-NetFirewallRule -AssociatedNetFirewallPortFilter $filter -ErrorAction Stop)) {
            if ($rule.Direction -ne 'Inbound') { continue }
            if ($rule.Action -ne 'Allow') { continue }
            if ("$($rule.Enabled)" -ne 'True') { continue }
            $found += $rule
        }
    }
    $found
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired' }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error: Prerequisite | Reason=Use64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Error: Prerequisite | Reason=SystemContextRequired'
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $state = Get-RdpEnabledState
    if ($null -eq $state) { Exit-Script 1 'Blocked | Reason=RemoteDesktopStateUnreadable' }

    $rules = @(Get-RdpFirewallRule)
    if (Test-RdpApproved) {
        Exit-Script 0 "NotApplicable | Reason=ApprovedDevice; RdpEnabled=$state; FirewallRules=$($rules.Count)"
    }
    if (-not $state -and $rules.Count -eq 0) { Exit-Script 0 'Healthy | RdpEnabled=False; FirewallRules=0' }
    if (Get-RdpPolicyState) {
        Exit-Script 1 "Blocked | Reason=EnabledByPolicy; RdpEnabled=$state; FirewallRules=$($rules.Count)"
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "Drift | Reason=RemediationDisabled; RdpEnabled=$state; FirewallRules=$($rules.Count)"
    }

    $disabledRules = 0
    $failedRules = 0
    if ($state) {
        $previous = (Get-ItemProperty -LiteralPath $TerminalServerKey -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections
        Set-ItemProperty -LiteralPath $TerminalServerKey -Name 'fDenyTSConnections' -Value 1 -Type DWord -ErrorAction Stop
        Write-IRTLog "RemoteDesktopDisabled | Previous=$previous"
    }
    if ($DisableFirewallRules) {
        foreach ($rule in $rules) {
            try {
                $rule | Set-NetFirewallRule -Enabled False -ErrorAction Stop
                $disabledRules++
            }
            catch {
                $failedRules++
                Write-IRTLog "FirewallRuleNotChanged | Name=$($rule.Name)"
            }
        }
    }

    $stateAfter = Get-RdpEnabledState
    $rulesAfter = @(Get-RdpFirewallRule)
    if ($null -eq $stateAfter) { Exit-Script 1 'Failed | Reason=RemoteDesktopStateUnreadable' }
    if ($stateAfter -or ($DisableFirewallRules -and $rulesAfter.Count -gt 0)) {
        Exit-Script 1 "Failed | RdpEnabled=$stateAfter; FirewallRules=$($rulesAfter.Count); Disabled=$disabledRules; Unchanged=$failedRules"
    }
    Exit-Script 0 "Fixed | RdpEnabled=False; FirewallRules=$($rulesAfter.Count); Disabled=$disabledRules; Unchanged=$failedRules"
}
catch {
    Exit-Script 1 ('Error: RemediationFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
