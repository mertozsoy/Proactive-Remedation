<#
.SYNOPSIS
  Remediation script for WDigest plaintext credential caching.

.DESCRIPTION
  Backs up the WDigest security provider key, sets UseLogonCredential to 0 and verifies the value. Exits 0 when WDigest caching is disabled, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$BackupRoot        = Join-Path $env:ProgramData 'IntuneRemediations\Backup\WDigestCredentialCaching'
$WDigestKey        = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
$WDigestKeyNative  = 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
$ValueName         = 'UseLogonCredential'
$ExpectedValue     = 0

$PackageName = 'WDigestCredentialCaching'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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

function Format-WDigestState { param($Value)
    'WDigest={0}; UseLogonCredential={1}; Expected={2}' -f (Get-WDigestText $Value), (Get-ValueText $Value), $ExpectedValue
}

function Test-WDigestDrift { param($Value)
    return ($null -ne $Value -and [int]$Value -ne $ExpectedValue)
}

function Save-RegistryBackup {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $target = Join-Path $BackupRoot ('WDigest-{0}.reg' -f $stamp)
    & reg.exe export $WDigestKeyNative $target /y | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-IRTLog 'Registry backup skipped, key cannot be exported' 'WARN' }
    else { Write-IRTLog "Registry backup written to $target" }
}

function Set-WDigestValue {
    if (-not (Test-Path -LiteralPath $WDigestKey)) { New-Item -Path $WDigestKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $WDigestKey -Name $ValueName -Value $ExpectedValue -Type DWord -ErrorAction Stop
}

try {
    $before = Get-WDigestValue

    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | $(Format-WDigestState $before)" }
    if (-not (Test-WDigestDrift -Value $before)) { Exit-Script 0 "Healthy | $(Format-WDigestState $before)" }

    Write-IRTLog "Drift found, previous value $(Get-ValueText $before)"
    Save-RegistryBackup
    Set-WDigestValue

    $after = Get-WDigestValue
    $result = 'Previous={0}; {1}' -f (Get-ValueText $before), (Format-WDigestState $after)

    if (-not (Test-WDigestDrift -Value $after)) { Exit-Script 0 "Fixed | $result" }
    Exit-Script 1 "Failed | Left=UseLogonCredential; $result"
}
catch {
    Exit-Script 1 ('Error: RemediationFailed | Type={0}; HResult={1}' -f $_.Exception.GetType().Name, $_.Exception.HResult)
}
