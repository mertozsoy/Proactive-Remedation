<#
.SYNOPSIS
  Detection script for an AD group missing from the local Administrators group.

.DESCRIPTION
  On a domain joined device the script reads the local Administrators group and checks whether the configured AD group is still a member. Exits 1 when the group is missing or cannot be verified, 0 when it is present or the device is not domain joined.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RequiredGroupName = ''
$RequiredGroupSid  = ''
$AdminGroupSid     = 'S-1-5-32-544'

$PackageName = 'DomainAdminsLocalGroup'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Resolve-GroupSid { param([string]$Name, [string]$Sid)
    if ($Sid) { return $Sid }
    try {
        $account = New-Object System.Security.Principal.NTAccount($Name)
        return $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
    }
    catch { return '' }
}
function Get-AdminMember {
    $sid = New-Object System.Security.Principal.SecurityIdentifier($AdminGroupSid)
    @(Get-LocalGroupMember -SID $sid -ErrorAction Stop)
}
function Test-GroupPresent { param([object[]]$Members, [string]$Name, [string]$Sid)
    if ($Sid) { return @($Members | Where-Object { $_.SID.Value -eq $Sid }).Count -gt 0 }
    return @($Members | Where-Object { $_.Name -eq $Name }).Count -gt 0
}

try {
    if ([string]::IsNullOrWhiteSpace($RequiredGroupName) -and [string]::IsNullOrWhiteSpace($RequiredGroupSid)) { Exit-Script 0 'NotApplicable | Reason=RequiredGroupNotConfigured' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=Requires64BitPowerShell'
    }
    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.LocalAccounts)) {
        Exit-Script 0 'NotApplicable | Reason=LocalAccountsUnavailable'
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if (-not $computer.PartOfDomain) { Exit-Script 0 'NotApplicable | Reason=NotDomainJoined' }

    $groupId = Resolve-GroupSid -Name $RequiredGroupName -Sid $RequiredGroupSid
    $members = @(Get-AdminMember)
    $present = Test-GroupPresent -Members $members -Name $RequiredGroupName -Sid $groupId

    if ($present) { Exit-Script 0 "Healthy | Group=$RequiredGroupName; Admins=$($members.Count)" }
    if (-not $groupId) {
        Exit-Script 1 "Unverified | Group=$RequiredGroupName; Admins=$($members.Count); Reason=GroupNotResolvable"
    }
    Exit-Script 1 "Missing | Group=$RequiredGroupName; Admins=$($members.Count)"
}
catch { Exit-Script 1 "Error: Failed | Reason=$($_.Exception.GetType().Name)" }
