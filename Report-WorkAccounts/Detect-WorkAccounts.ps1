<#
.SYNOPSIS
  Detection script for multiple or foreign work accounts on the device.

.DESCRIPTION
  Collects the work accounts that are present on the device from three sources: Entra ID user profiles, Office identities of the signed-in user and MDM enrollment records. Compares the account domains with the allowed domain list. Exits 1 if the account count is above the limit or a domain is not allowed, 0 otherwise. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MaxWorkAccounts        = 1
$AllowedDomains         = @()
$IncludeOfficeIdentity  = $true
$IncludeEnrollments     = $true
$MaxListedDomains       = 8

$PackageName  = 'WorkAccounts'
$Phase        = 'Detect'
$LogDir       = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile      = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-AccountDomain { param([string]$Account)
    $value = "$Account".Trim()
    if ($value.Contains('\')) { $value = ($value -split '\\')[-1] }
    if (-not $value.Contains('@')) { return '' }
    return ($value -split '@')[-1].Trim().ToLowerInvariant()
}

function Get-FirstAccountValue { param($PropertyList, [string[]]$NamePatterns)
    foreach ($pattern in $NamePatterns) {
        foreach ($property in $PropertyList) {
            if ($property.Name -notlike $pattern) { continue }
            $value = "$($property.Value)".Trim()
            if ($value -and $value.Contains('@')) { return $value }
        }
    }
    return ''
}

function Get-ProfileAccount {
    $list = New-Object System.Collections.Generic.List[object]
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special=False' -ErrorAction SilentlyContinue)
    foreach ($userProfile in $profiles) {
        $sid = "$($userProfile.SID)"
        if (-not $sid) { continue }
        $name = ''
        try { $name = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount]).Value } catch { $name = '' }
        $isEntra = $sid.StartsWith('S-1-12-1-') -or $name.StartsWith('AzureAD\')
        if (-not $isEntra) { continue }
        if (-not $name.Contains('@')) { $name = 'profile:{0}' -f $sid.Substring([Math]::Max(0, $sid.Length - 8)) }
        $list.Add([pscustomobject]@{ Account = $name; Source = 'Profile' })
    }
    return $list
}

function Get-OfficeAccount {
    $list = New-Object System.Collections.Generic.List[object]
    $root = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Identity\Identities'
    if (-not (Test-Path -LiteralPath $root)) { return $list }
    foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        $propertyList = @((Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
        $account = Get-FirstAccountValue -PropertyList $propertyList -NamePatterns @('*EmailAddress*', '*Username*', '*Upn*')
        if (-not $account) { Write-IRTLog "Office identity without a mail value: $($key.PSChildName)" 'WARN'; continue }
        $list.Add([pscustomobject]@{ Account = $account; Source = 'Office' })
    }
    return $list
}

function Get-EnrollmentAccount {
    $list = New-Object System.Collections.Generic.List[object]
    $root = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    try { $keys = @(Get-ChildItem -LiteralPath $root -ErrorAction Stop) }
    catch { Write-IRTLog "Enrollment key not readable: $($_.Exception.Message)" 'WARN'; return $list }
    foreach ($key in $keys) {
        $propertyList = @((Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
        $account = Get-FirstAccountValue -PropertyList $propertyList -NamePatterns @('*Upn*', '*Account*', '*User*')
        if (-not $account) { continue }
        $list.Add([pscustomobject]@{ Account = $account; Source = 'Enrollment' })
    }
    return $list
}

try {
    $accounts = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Get-ProfileAccount)) { $accounts.Add($entry) }
    if ($IncludeOfficeIdentity) { foreach ($entry in @(Get-OfficeAccount)) { $accounts.Add($entry) } }
    if ($IncludeEnrollments)    { foreach ($entry in @(Get-EnrollmentAccount)) { $accounts.Add($entry) } }

    $unique = @{}
    foreach ($entry in $accounts) {
        $key = $entry.Account.Trim().ToLowerInvariant()
        if (-not $key) { continue }
        $domain = Get-AccountDomain -Account $entry.Account
        if ($unique.ContainsKey($key)) { $unique[$key].Domain = $domain; continue }
        $unique[$key] = [pscustomobject]@{ Account = $entry.Account; Domain = $domain }
    }

    $sourceText = 'Profiles={0}; Office={1}; Enrollments={2}' -f @($accounts | Where-Object { $_.Source -eq 'Profile' }).Count,
        @($accounts | Where-Object { $_.Source -eq 'Office' }).Count,
        @($accounts | Where-Object { $_.Source -eq 'Enrollment' }).Count

    if ($unique.Count -eq 0) { Exit-Script 0 "NotApplicable | WorkAccounts=0; $sourceText" }

    $domains = @{}
    foreach ($item in $unique.Values) {
        Write-IRTLog ('Account={0} Domain={1}' -f $item.Account, $item.Domain)
        if (-not $item.Domain) { continue }
        if ($domains.ContainsKey($item.Domain)) { $domains[$item.Domain]++ } else { $domains[$item.Domain] = 1 }
    }

    $allowed = @($AllowedDomains | ForEach-Object { "$_".Trim().ToLowerInvariant() } | Where-Object { $_ })
    $foreign = @()
    if ($allowed.Count -gt 0) {
        $foreign = @($domains.Keys | Where-Object { $allowed -notcontains $_ } | Sort-Object)
    }

    $listed = @($domains.Keys | Sort-Object | Select-Object -First $MaxListedDomains | ForEach-Object { '{0}({1})' -f $_, $domains[$_] })
    $more = [math]::Max(0, $domains.Count - $MaxListedDomains)
    $domainText = if ($listed.Count -gt 0) { $listed -join ',' } else { 'None' }
    if ($more -gt 0) { $domainText += ",+$more" }

    $summary = 'Accounts={0}; Max={1}; Foreign={2}; Domains={3}; {4}' -f $unique.Count, $MaxWorkAccounts, $foreign.Count, $domainText, $sourceText

    if ($foreign.Count -gt 0) { Exit-Script 1 "Foreign ($($foreign.Count)) | $summary" }
    if ($MaxWorkAccounts -gt 0 -and $unique.Count -gt $MaxWorkAccounts) { Exit-Script 1 "Multiple ($($unique.Count)) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
