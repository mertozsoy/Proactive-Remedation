<#
.SYNOPSIS
  Restores missing standalone FortiClient SSL VPN tunnel settings.

.DESCRIPTION
  Creates an approved basic SSL VPN profile or adds missing values on FortiClient VPN 7.x. Existing conflicting values are not overwritten. Verifies all configured values before returning exit 0; failures return exit 1.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$TunnelName = 'CorporateVPN'
$VpnServer = ''
$TunnelDescription = 'Corporate SSL VPN'
$StandaloneDeploymentConfirmed = $false
$ClientExecutable = Join-Path $env:ProgramFiles 'Fortinet\FortiClient\FortiClient.exe'

$PackageName = 'FortiClientVpnTunnel'
$Phase = 'Remediate'
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
function Get-TunnelState { param([string]$Path, [array]$Expected)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Present = $false; Missing = @($Expected); Conflicts = 0 }
    }
    $key = Get-Item -LiteralPath $Path
    $missing = @()
    $conflicts = 0
    try {
        $names = @($key.GetValueNames())
        foreach ($setting in $Expected) {
            if ($names -notcontains $setting.Name) { $missing += $setting; continue }
            if ($key.GetValueKind($setting.Name).ToString() -ne $setting.Kind -or
                [string]$key.GetValue($setting.Name) -cne [string]$setting.Value) { $conflicts++ }
        }
    }
    finally { $key.Close() }
    return [pscustomobject]@{ Present = $true; Missing = @($missing); Conflicts = $conflicts }
}

try {
    $ErrorActionPreference = 'Stop'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=Requires64BitPowerShell'
    }
    if (-not (Test-Path -LiteralPath $ClientExecutable -PathType Leaf)) {
        Exit-Script 0 'NotApplicable | Reason=FortiClientMissing'
    }
    $version = (Get-Item -LiteralPath $ClientExecutable).VersionInfo
    if ($version.FileMajorPart -ne 7) { Exit-Script 0 'NotApplicable | Reason=UnsupportedClientVersion' }
    if (-not $StandaloneDeploymentConfirmed) {
        Exit-Script 0 'NotApplicable | Reason=StandaloneScopeNotConfirmed'
    }
    if ($TunnelName -notmatch '^[A-Za-z0-9][A-Za-z0-9 _-]{0,63}$' -or
        [string]::IsNullOrWhiteSpace($VpnServer) -or $VpnServer -match '[\s/\\;]' -or
        $VpnServer -match '(?i)(example\.(com|net|org)|contoso\.|\.invalid)') {
        Exit-Script 1 'Failed | Reason=ConfigureTunnelNameAndServer'
    }
    $root = 'HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels'
    $path = Join-Path $root $TunnelName
    $expected = @(
        @{ Name = 'Description'; Kind = 'String'; Value = $TunnelDescription }
        @{ Name = 'Server'; Kind = 'String'; Value = $VpnServer }
        @{ Name = 'promptusername'; Kind = 'DWord'; Value = 1 }
        @{ Name = 'promptcertificate'; Kind = 'DWord'; Value = 0 }
    )
    $state = Get-TunnelState -Path $path -Expected $expected
    if ($state.Conflicts -gt 0) {
        Exit-Script 1 "Failed | Reason=ExistingSettingsConflict; Conflicts=$($state.Conflicts); Changed=0"
    }
    if ($state.Present -and $state.Missing.Count -eq 0) {
        Exit-Script 0 'Healthy | TunnelPresent=1; VerifiedValues=4'
    }
    if (-not $state.Present) {
        if (-not (Test-Path -LiteralPath $root)) { New-Item -Path $root -Force | Out-Null }
        New-Item -Path $path | Out-Null
    }
    $added = 0
    foreach ($setting in $state.Missing) {
        $current = Get-TunnelState -Path $path -Expected $expected
        if ($current.Conflicts -gt 0) {
            Exit-Script 1 "Failed | Reason=ConcurrentSettingsChange; AddedValues=$added"
        }
        if (@($current.Missing | Where-Object { $_.Name -eq $setting.Name }).Count -gt 0) {
            New-ItemProperty -LiteralPath $path -Name $setting.Name -PropertyType $setting.Kind -Value $setting.Value | Out-Null
            $added++
        }
    }
    $verified = Get-TunnelState -Path $path -Expected $expected
    if (-not $verified.Present -or $verified.Missing.Count -gt 0 -or $verified.Conflicts -gt 0) {
        Exit-Script 1 "Failed | Reason=VerificationFailed; AddedValues=$added"
    }
    Exit-Script 0 "Fixed | TunnelPresent=1; AddedValues=$added; VerifiedValues=4"
}
catch { Exit-Script 1 ('Error: Failed | Reason=RestoreError; Type={0}' -f $_.Exception.GetType().Name) }
