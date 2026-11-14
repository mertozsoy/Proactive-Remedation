<#
.SYNOPSIS
  Detection script for the DNS suffix search list on Microsoft Entra joined devices.

.DESCRIPTION
  Compares the global DNS suffix search list with the suffixes defined in $ExpectedSuffixes. Exits 1 if a suffix is missing, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ExpectedSuffixes      = @()
$SkipWhenPolicyPresent = $true
$PolicySearchListKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'

$PackageName = 'DnsSuffixSearchList'
$Phase       = 'Detect'
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
    $missing = @($expected | Where-Object { $current -notcontains $_ })
    if ($missing.Count -eq 0) { Exit-Script 0 "Healthy | Suffixes=$($expected -join ','); Count=$($current.Count)" }

    Exit-Script 1 "Drift | Missing=$($missing -join ','); Current=$($current -join ',')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
