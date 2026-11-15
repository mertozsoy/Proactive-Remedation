<#
.SYNOPSIS
  Remediation script that grants local admin to the mapped device user.

.DESCRIPTION
  Adds the mapped user to Administrators (S-1-5-32-544) only when that account has a profile on this device. Report only by default. Exits 0 if fixed or healthy, 1 if the user is still missing or remediation is disabled.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedDeviceUsers = @{}
$EnableRemediation = $false

$PackageName = 'DevicePrimaryUserAdmin'
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

function Get-ProfileSidMap {
    $map = @{}
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
        $path = (Get-ItemProperty -LiteralPath $key.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if ($path) {
            $map[$key.PSChildName] = @{ Leaf = (Split-Path -Path $path -Leaf); Sid = $key.PSChildName }
        }
    }
    $map
}

function Get-AccountSid { param([string]$Account)
    try {
        $ntAccount = [System.Security.Principal.NTAccount]::new($Account)
        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        return $sid.Value
    }
    catch { return $null }
}

function Get-DeviceKey {
    $keys = @()
    if ($env:COMPUTERNAME) { $keys += $env:COMPUTERNAME }
    $serial = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
    if ($serial) { $keys += ([string]$serial).Trim() }
    $keys
}

function Get-MappedAccount {
    param([hashtable]$Profiles)
    $result = @()
    foreach ($account in $script:Approved) {
        $sid = Get-AccountSid -Account $account
        $accountLeaf = $account.Split('\')[-1]
        $leafCandidates = @($accountLeaf)
        if ($accountLeaf -match '@') { $leafCandidates += $accountLeaf.Split('@')[0] }
        $hasProfile = $false
        if ($sid -and $Profiles.ContainsKey($sid)) {
            $hasProfile = $true
        }
        else {
            $isEntra = $account -like 'AzureAD\*'
            foreach ($profileEntry in $Profiles.Values) {
                if ($isEntra -and $profileEntry.Sid -notlike 'S-1-12-1-*') { continue }
                foreach ($candidate in $leafCandidates) {
                    if ($profileEntry.Leaf -ieq $candidate) { $hasProfile = $true; break }
                }
                if ($hasProfile) { break }
            }
        }
        if ($hasProfile) {
            $result += [pscustomobject]@{ Account = $account; Sid = $sid }
        }
    }
    $result
}

try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.LocalAccounts)) {
        Exit-Script 0 'NotApplicable | Reason=LocalAccountsUnavailable'
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $script:Approved = @()
    foreach ($deviceKey in Get-DeviceKey) {
        if ($ApprovedDeviceUsers.ContainsKey($deviceKey)) {
            $script:Approved += @($ApprovedDeviceUsers[$deviceKey])
        }
    }
    $script:Approved = @($script:Approved | Sort-Object -Unique)
    if ($script:Approved.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoDeviceMapping' }

    $profiles = Get-ProfileSidMap
    $mapped = @(Get-MappedAccount -Profiles $profiles)
    if ($mapped.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoProfile' }

    $adminSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $members = @(Get-LocalGroupMember -SID $adminSid -ErrorAction Stop)

    $targets = @()
    foreach ($item in $mapped) {
        $inGroup = $false
        if ($item.Sid) {
            $inGroup = @($members | Where-Object { $_.SID.Value -eq $item.Sid }).Count -gt 0
        }
        if (-not $inGroup) {
            $inGroup = @($members | Where-Object { $_.Name -ieq $item.Account }).Count -gt 0
        }
        if (-not $inGroup) { $targets += $item }
    }

    if ($targets.Count -eq 0) { Exit-Script 0 "Healthy | Approved=$($mapped.Count); Missing=0" }
    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Approved=$($mapped.Count); Missing=$($targets.Count); Enabled=No"
    }

    $added = 0
    foreach ($target in $targets) {
        try {
            Add-LocalGroupMember -SID $adminSid -Member $target.Account -ErrorAction Stop
            $added++
            Write-IRTLog "Account added to Administrators: mapped user with profile"
        }
        catch {
            Write-IRTLog "Add failed: $($_.Exception.GetType().Name)" 'WARN'
        }
    }

    $members = @(Get-LocalGroupMember -SID $adminSid -ErrorAction Stop)
    $left = 0
    foreach ($item in $mapped) {
        $inGroup = $false
        if ($item.Sid) {
            $inGroup = @($members | Where-Object { $_.SID.Value -eq $item.Sid }).Count -gt 0
        }
        if (-not $inGroup) {
            $inGroup = @($members | Where-Object { $_.Name -ieq $item.Account }).Count -gt 0
        }
        if (-not $inGroup) { $left++ }
    }

    if ($left -gt 0) { Exit-Script 1 "Failed | Approved=$($mapped.Count); Added=$added; Missing=$left" }
    Exit-Script 0 "Fixed | Approved=$($mapped.Count); Added=$added; Missing=0"
}
catch { Exit-Script 1 "Error: Failed | Reason=RemediationFailed; Type=$($_.Exception.GetType().Name)" }
