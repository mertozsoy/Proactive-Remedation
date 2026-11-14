<#
.SYNOPSIS
  Detection script for Remote Desktop exposure on clients that are not approved for RDP.

.DESCRIPTION
  Reads the Remote Desktop state and every enabled inbound firewall rule that opens TCP or UDP port 3389.
  Exits 1 when a client is reachable over RDP without approval or when the state is policy owned, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedGroupName   = 'RDP-Approved'
$ApprovedDeviceNames = @()
$RdpManagedByPolicy  = $false

$PackageName = 'RdpAccess'
$Phase       = 'Detect'
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
    $approved = Test-RdpApproved
    if ($approved) { Exit-Script 0 "NotApplicable | Reason=ApprovedDevice; RdpEnabled=$state; FirewallRules=$($rules.Count)" }
    if (-not $state -and $rules.Count -eq 0) { Exit-Script 0 'Healthy | RdpEnabled=False; FirewallRules=0' }

    if (Get-RdpPolicyState) {
        Exit-Script 1 "Blocked | Reason=EnabledByPolicy; RdpEnabled=$state; FirewallRules=$($rules.Count)"
    }
    Exit-Script 1 "Drift | RdpEnabled=$state; FirewallRules=$($rules.Count); Approval=Missing"
}
catch {
    Exit-Script 1 ('Error: AssessmentFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
