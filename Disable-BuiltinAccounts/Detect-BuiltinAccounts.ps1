<#
.SYNOPSIS
  Detection script for enabled Guest and explicitly selected built-in accounts.

.DESCRIPTION
  Identifies local accounts by RID regardless of language or renaming. Guest is
  targeted by default. Other system-managed accounts require explicit opt-in.
  Exits 1 for enabled targets or blocked assessment, 0 for healthy or inapplicable devices.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$DisableDefaultAccount = $false
$DisableWdagUtilityAccount = $false
$AccountsManagedByPolicy = $false

$PackageName = 'BuiltinAccounts'
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

function Get-BuiltinAccountState {
    foreach ($account in @(Get-LocalUser -ErrorAction Stop)) {
        if ($account.SID.Value -notmatch '^S-1-5-21-\d+-\d+-\d+-(501|503|504)$') { continue }
        $rid = [int]($account.SID.Value.Split('-')[-1])
        $selected = ($rid -eq 501) -or ($rid -eq 503 -and $DisableDefaultAccount) -or ($rid -eq 504 -and $DisableWdagUtilityAccount)
        [pscustomobject]@{ Rid = $rid; Sid = $account.SID; Enabled = $account.Enabled; Selected = $selected }
    }
}

function Get-AccountPolicyBlock { param([bool]$DomainJoined, [bool]$CheckGuest)
    if ($AccountsManagedByPolicy) { return 'DeclaredPolicyOwner' }
    if ($DomainJoined) { return 'DomainJoinedPolicyReview' }
    if ($CheckGuest) {
        try {
            $policies = @(Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_Policy_Result01_LocalPoliciesSecurityOptions02' -ErrorAction Stop)
            foreach ($policy in $policies) {
                $setting = $policy.CimInstanceProperties['Accounts_EnableGuestAccountStatus']
                if ($null -eq $setting -or $null -eq $setting.Value) { return 'PolicyStateUnavailable' }
                if ([int]$setting.Value -eq 1) { return 'GuestEnabledByPolicy' }
                if ([int]$setting.Value -ne 0) { return 'PolicyStateUnavailable' }
            }
        }
        catch { return 'PolicyStateUnavailable' }
    }
    return ''
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | Reason=WindowsClientRequired' }
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Error: Prerequisite | Reason=Use64BitPowerShell' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Exit-Script 1 'Error: Prerequisite | Reason=SystemContextRequired'
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $states = @(Get-BuiltinAccountState)
    $targets = @($states | Where-Object Selected)
    if ($targets.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=TargetAccountsAbsent' }
    $enabled = @($targets | Where-Object Enabled)
    $observed = @($states | Where-Object { $_.Enabled -and -not $_.Selected }).Count
    $scope = ($targets.Rid | Sort-Object) -join ','
    if ($enabled.Count -eq 0) { Exit-Script 0 "Healthy | EnabledTargets=0; ObservedOnly=$observed; Scope=$scope" }
    $rids = ($enabled.Rid | Sort-Object) -join ','
    $reason = Get-AccountPolicyBlock -DomainJoined $computer.PartOfDomain -CheckGuest ($enabled.Rid -contains 501)
    if ($reason) { Exit-Script 1 "Blocked | EnabledTargets=$($enabled.Count); Rids=$rids; Reason=$reason; ObservedOnly=$observed" }
    Exit-Script 1 "Drift | EnabledTargets=$($enabled.Count); Rids=$rids; ObservedOnly=$observed"
}
catch {
    Exit-Script 1 ('Error: AssessmentFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
