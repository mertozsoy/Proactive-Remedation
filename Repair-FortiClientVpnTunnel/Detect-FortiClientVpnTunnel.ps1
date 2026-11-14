<#
.SYNOPSIS
  Detects missing standalone FortiClient SSL VPN tunnel settings.

.DESCRIPTION
  Checks an approved basic SSL VPN profile on FortiClient VPN 7.x. Exits 1 for missing or conflicting settings, 0 when healthy or not applicable. Does not test VPN connectivity.

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
    if (-not (Test-Path -LiteralPath $path)) {
        Exit-Script 1 'Drift | MissingTunnel=1; MissingValues=4; Conflicts=0'
    }
    $expected = @(
        @{ Name = 'Description'; Kind = 'String'; Value = $TunnelDescription }
        @{ Name = 'Server'; Kind = 'String'; Value = $VpnServer }
        @{ Name = 'promptusername'; Kind = 'DWord'; Value = 1 }
        @{ Name = 'promptcertificate'; Kind = 'DWord'; Value = 0 }
    )
    $key = Get-Item -LiteralPath $path
    $missing = 0
    $conflicts = 0
    try {
        $names = @($key.GetValueNames())
        foreach ($setting in $expected) {
            if ($names -notcontains $setting.Name) { $missing++; continue }
            if ($key.GetValueKind($setting.Name).ToString() -ne $setting.Kind -or
                [string]$key.GetValue($setting.Name) -cne [string]$setting.Value) { $conflicts++ }
        }
    }
    finally { $key.Close() }
    if ($missing -gt 0 -or $conflicts -gt 0) {
        Exit-Script 1 "Drift | MissingTunnel=0; MissingValues=$missing; Conflicts=$conflicts"
    }
    Exit-Script 0 'Healthy | TunnelPresent=1; VerifiedValues=4'
}
catch { Exit-Script 1 ('Error: Failed | Reason=InspectionError; Type={0}' -f $_.Exception.GetType().Name) }
