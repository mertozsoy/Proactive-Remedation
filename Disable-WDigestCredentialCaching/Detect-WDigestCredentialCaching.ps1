<#
.SYNOPSIS
  Detection script for WDigest plaintext credential caching.

.DESCRIPTION
  Reads UseLogonCredential under the WDigest security provider key. Exits 1 if the value is set to anything other than 0, 0 if the value is 0 or not set.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WDigestKey    = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
$ValueName     = 'UseLogonCredential'
$ExpectedValue = 0

$PackageName = 'WDigestCredentialCaching'
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

function Get-WDigestValue {
    try { $value = (Get-ItemProperty -LiteralPath $WDigestKey -Name $ValueName -ErrorAction Stop).$ValueName }
    catch { return $null }
    if ($null -eq $value) { return $null }
    return [int]$value
}

function Get-ValueText { param($Value)
    if ($null -eq $Value) { return 'Unset' }
    return [string]$Value
}

function Get-WDigestText { param($Value)
    if ($null -eq $Value) { return 'Disabled' }
    if ([int]$Value -eq 0) { return 'Disabled' }
    return 'Enabled'
}

try {
    if (-not (Test-Path -LiteralPath $WDigestKey)) { Exit-Script 0 'Healthy | WDigestKey=Missing; WDigest=Disabled' }

    $value   = Get-WDigestValue
    $summary = 'WDigest={0}; UseLogonCredential={1}; Expected={2}' -f (Get-WDigestText $value), (Get-ValueText $value), $ExpectedValue

    if ($null -ne $value -and [int]$value -ne $ExpectedValue) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
