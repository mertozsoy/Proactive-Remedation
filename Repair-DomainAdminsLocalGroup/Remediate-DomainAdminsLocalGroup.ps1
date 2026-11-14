<#
.SYNOPSIS
  Remediation script that adds the configured AD group back to the local Administrators group.

.DESCRIPTION
  Checks the local Administrators group on a domain joined device. When the configured AD group is missing the script resolves it to a SID, adds it to the group and verifies the membership. Exits 0 when the group is present or added, 1 when it cannot be resolved or added.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RequiredGroupName = ''
$RequiredGroupSid  = ''
$AdminGroupSid     = 'S-1-5-32-544'
$EnableRemediation = $true

$PackageName = 'DomainAdminsLocalGroup'
$Phase       = 'Remediate'
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

    $adminSid = New-Object System.Security.Principal.SecurityIdentifier($AdminGroupSid)
    $members = @(Get-AdminMember)
    $groupId = Resolve-GroupSid -Name $RequiredGroupName -Sid $RequiredGroupSid

    if (Test-GroupPresent -Members $members -Name $RequiredGroupName -Sid $groupId) {
        Exit-Script 0 "Healthy | Group=$RequiredGroupName; Admins=$($members.Count)"
    }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Group=$RequiredGroupName; Admins=$($members.Count); Added=0"
    }
    if (-not $groupId) {
        Exit-Script 1 "Blocked | Reason=GroupNotResolvable; Group=$RequiredGroupName; Added=0"
    }

    try {
        Add-LocalGroupMember -SID $adminSid -Member $groupId -ErrorAction Stop
    }
    catch {
        Write-IRTLog "Add by SID failed: $($_.Exception.Message)"
        Exit-Script 1 "Blocked | Reason=AddFailed; Group=$RequiredGroupName; Added=0"
    }

    $after = @(Get-AdminMember)
    if (-not (Test-GroupPresent -Members $after -Name $RequiredGroupName -Sid $groupId)) {
        Exit-Script 1 "Failed | Group=$RequiredGroupName; Added=0; Admins=$($after.Count)"
    }
    Exit-Script 0 "Fixed | Group=$RequiredGroupName; Added=1; Admins=$($after.Count)"
}
catch { Exit-Script 1 "Error: Failed | Reason=$($_.Exception.GetType().Name)" }
