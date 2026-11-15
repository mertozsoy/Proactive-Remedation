<#
.SYNOPSIS
  Detection script for missing local admin rights of the mapped device user.

.DESCRIPTION
  Reads the device to user mapping, resolves the account and its profile, and checks direct membership in Administrators (S-1-5-32-544). Exits 1 if the mapped user with a profile is missing from the group, 0 when healthy or not applicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ApprovedDeviceUsers = @{}

$PackageName = 'DevicePrimaryUserAdmin'
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

try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.LocalAccounts)) {
        Exit-Script 0 'NotApplicable | Reason=LocalAccountsUnavailable'
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $approved = @()
    foreach ($deviceKey in Get-DeviceKey) {
        if ($ApprovedDeviceUsers.ContainsKey($deviceKey)) {
            $approved += @($ApprovedDeviceUsers[$deviceKey])
        }
    }
    $approved = @($approved | Sort-Object -Unique)
    if ($approved.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoDeviceMapping' }

    $profiles = Get-ProfileSidMap
    $adminSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $members = @(Get-LocalGroupMember -SID $adminSid -ErrorAction Stop)

    $withProfile = 0
    $missing = 0
    foreach ($account in $approved) {
        $sid = Get-AccountSid -Account $account
        $accountLeaf = $account.Split('\')[-1]
        $leafCandidates = @($accountLeaf)
        if ($accountLeaf -match '@') { $leafCandidates += $accountLeaf.Split('@')[0] }
        $hasProfile = $false
        if ($sid -and $profiles.ContainsKey($sid)) {
            $hasProfile = $true
        }
        else {
            $isEntra = $account -like 'AzureAD\*'
            foreach ($profileEntry in $profiles.Values) {
                if ($isEntra -and $profileEntry.Sid -notlike 'S-1-12-1-*') { continue }
                foreach ($candidate in $leafCandidates) {
                    if ($profileEntry.Leaf -ieq $candidate) { $hasProfile = $true; break }
                }
                if ($hasProfile) { break }
            }
        }
        if (-not $hasProfile) { continue }
        $withProfile++

        $inGroup = $false
        if ($sid) {
            $inGroup = @($members | Where-Object { $_.SID.Value -eq $sid }).Count -gt 0
        }
        if (-not $inGroup) {
            $inGroup = @($members | Where-Object { $_.Name -ieq $account }).Count -gt 0
        }
        if (-not $inGroup) { $missing++ }
    }

    if ($withProfile -eq 0) { Exit-Script 0 'NotApplicable | Reason=NoProfile' }
    if ($missing -eq 0) { Exit-Script 0 "Healthy | Approved=$withProfile; Missing=0" }
    Exit-Script 1 "Drift | Approved=$withProfile; Missing=$missing"
}
catch { Exit-Script 1 "Error: Failed | Reason=InspectionFailed; Type=$($_.Exception.GetType().Name)" }
