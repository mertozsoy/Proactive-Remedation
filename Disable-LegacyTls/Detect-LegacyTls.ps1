<#
.SYNOPSIS
  Detection script for legacy TLS 1.0 and TLS 1.1 settings.

.DESCRIPTION
  Checks the SCHANNEL protocol keys for TLS 1.0 and TLS 1.1 and the .NET Framework strong crypto values. Exits 1 if a legacy protocol is not disabled or .NET does not follow the OS TLS defaults.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$Protocols         = @('TLS 1.0', 'TLS 1.1')
$IncludeServerSide = $true
$DotNetVersions    = @('v4.0.30319', 'v2.0.50727')

$PackageName = 'LegacyTls'
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

try {
    $issues     = New-Object System.Collections.Generic.List[string]
    $schannel   = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
    $sides      = @('Client')
    if ($IncludeServerSide) { $sides += 'Server' }

    foreach ($protocol in $Protocols) {
        foreach ($side in $sides) {
            $key   = Join-Path $schannel "$protocol\$side"
            $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            if ($null -eq $props -or $props.Enabled -ne 0 -or $props.DisabledByDefault -ne 1) {
                $issues.Add(('{0}{1}' -f ($protocol -replace ' ', ''), $side))
            }
        }
    }

    $netRoots = @{ 'NET64' = 'HKLM:\SOFTWARE\Microsoft\.NETFramework'; 'NET32' = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework' }
    $netChecked = 0
    foreach ($label in $netRoots.Keys) {
        foreach ($version in $DotNetVersions) {
            $key = Join-Path $netRoots[$label] $version
            if (-not (Test-Path -LiteralPath $key)) { continue }
            $netChecked++
            $props = Get-ItemProperty -LiteralPath $key
            if ($props.SchUseStrongCrypto -ne 1 -or $props.SystemDefaultTlsVersions -ne 1) { $issues.Add("$label-$version") }
        }
    }

    $summary = 'Protocols={0}; Sides={1}; DotNetKeys={2}' -f ($Protocols -join ','), ($sides -join '+'), $netChecked
    if ($issues.Count -gt 0) { Exit-Script 1 "Unhealthy ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
