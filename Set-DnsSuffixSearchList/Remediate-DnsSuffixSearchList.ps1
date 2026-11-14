<#
.SYNOPSIS
  Remediation script that adds the missing suffixes to the DNS suffix search list.

.DESCRIPTION
  Merges the suffixes defined in $ExpectedSuffixes into the global DNS suffix search list and verifies the result. Exits 0 if every suffix is present, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedSuffixes      = @()
$SkipWhenPolicyPresent = $true
$FlushDnsCache         = $true
$PolicySearchListKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'

$PackageName = 'DnsSuffixSearchList'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-SuffixList {
    $setting = Get-DnsClientGlobalSetting -ErrorAction Stop
    @($setting.SuffixSearchList | Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('.') } | Where-Object { $_ })
}

try {
    $expected = @($ExpectedSuffixes | Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('.') } | Where-Object { $_ } | Select-Object -Unique)
    if ($expected.Count -eq 0) { Exit-Script 0 'NotApplicable | ExpectedSuffixes is empty' }

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($computer.PartOfDomain) { Exit-Script 0 "NotApplicable | DomainJoined=True; Domain=$($computer.Domain)" }

    if ($SkipWhenPolicyPresent -and (Test-Path -LiteralPath $PolicySearchListKey)) {
        Exit-Script 0 'NotApplicable | PolicyManaged=True; Source=DNSClient policy'
    }

    $current = @(Get-SuffixList)
    $merged  = @($current)
    $added   = @()
    foreach ($suffix in $expected) {
        if ($merged -notcontains $suffix) { $merged += $suffix; $added += $suffix }
    }

    if ($added.Count -eq 0) { Exit-Script 0 "Healthy | Suffixes=$($current -join ',')" }

    Set-DnsClientGlobalSetting -SuffixSearchList $merged -ErrorAction Stop
    Write-IRTLog "Suffix list updated: $($merged -join ',')"

    if ($FlushDnsCache) {
        try { Clear-DnsClientCache -ErrorAction Stop } catch { Write-IRTLog 'DNS cache flush skipped' -Level 'WARN' }
    }

    $after = @(Get-SuffixList)
    $missing = @($expected | Where-Object { $after -notcontains $_ })
    if ($missing.Count -gt 0) { Exit-Script 1 "Failed | Missing=$($missing -join ','); Current=$($after -join ',')" }

    Exit-Script 0 "Fixed | Added=$($added -join ','); SearchList=$($after -join ',')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
