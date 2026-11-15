<#
.SYNOPSIS
  Detection script for static DNS servers left on physical adapters after a VPN session.

.DESCRIPTION
  Reads the static DNS value of every physical adapter that uses DHCP and has DHCP-provided DNS servers. Exits 1 if an adapter still holds a static DNS list that differs from the DHCP list, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AddressFamily          = 'IPv4'
$OnlyConnectedAdapter   = $true
$RequireDhcpDns         = $true
$ReportOnlyWhenDifferent = $true
$ExcludeInterfaceAlias  = @()
$VpnAdapterPatterns     = @('VPN', 'TAP-Windows', 'OpenVPN', 'WireGuard', 'Fortinet', 'AnyConnect', 'GlobalProtect', 'PANGP', 'SonicWall', 'Juniper', 'Pulse Secure', 'Ivanti', 'Check Point')

$PackageName = 'VpnLeftDns'
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

$TcpipInterfaces = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
$script:EvaluatedAdapters = 0

function Test-VpnAdapterConnected {
    $physicalIndexes = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { $_.ifIndex })
    foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue)) {
        if ($physicalIndexes -contains $adapter.ifIndex) { continue }
        if ($adapter.Status -ne 'Up') { continue }
        $text = '{0} {1}' -f $adapter.Name, $adapter.InterfaceDescription
        foreach ($pattern in $VpnAdapterPatterns) {
            if ($text -match [regex]::Escape($pattern)) { return $true }
        }
    }
    $false
}

function Get-DnsRegistryList { param([string]$InterfaceGuid, [string]$ValueName)
    $keyName = $InterfaceGuid.Trim()
    if (-not $keyName.StartsWith('{')) { $keyName = '{' + $keyName + '}' }
    $key = Join-Path $TcpipInterfaces $keyName
    $raw = (Get-ItemProperty -LiteralPath $key -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    if (-not $raw) { return @() }
    @($raw -split '[,\s]+' | Where-Object { $_ })
}

function Test-SameDnsList { param([string[]]$First, [string[]]$Second)
    $a = (@($First | Sort-Object) -join ',')
    $b = (@($Second | Sort-Object) -join ',')
    $a -eq $b
}

function Get-StaleDnsAdapter {
    $result = @()
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        if ($ExcludeInterfaceAlias -contains $adapter.Name) { continue }
        if ($OnlyConnectedAdapter -and $adapter.Status -ne 'Up') { continue }
        $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily $AddressFamily -ErrorAction SilentlyContinue
        if ($null -eq $ipInterface) { continue }
        if ($ipInterface.Dhcp -ne 'Enabled') { continue }
        $script:EvaluatedAdapters++
        $guid = [string]$adapter.InterfaceGuid
        $static = @(Get-DnsRegistryList -InterfaceGuid $guid -ValueName 'NameServer')
        if ($static.Count -eq 0) { continue }
        $dhcpServers = @(Get-DnsRegistryList -InterfaceGuid $guid -ValueName 'DhcpNameServer')
        if ($RequireDhcpDns -and $dhcpServers.Count -eq 0) { continue }
        if ($ReportOnlyWhenDifferent -and (Test-SameDnsList -First $static -Second $dhcpServers)) { continue }
        $result += [pscustomobject]@{
            Name   = $adapter.Name
            Index  = $adapter.ifIndex
            Guid   = $guid
            Static = $static
            Dhcp   = $dhcpServers
        }
    }
    $result
}

try {
    if (Test-VpnAdapterConnected) { Exit-Script 0 'NotApplicable | VpnActive=True' }

    $stale = @(Get-StaleDnsAdapter)
    if ($script:EvaluatedAdapters -eq 0) { Exit-Script 0 'NotApplicable | DhcpAdapters=0' }
    if ($stale.Count -eq 0) { Exit-Script 0 "Healthy | DhcpAdapters=$script:EvaluatedAdapters; StaticDns=0" }

    $details = ($stale | ForEach-Object { '{0}={1}' -f $_.Name, ($_.Static -join '|') }) -join '; '
    Exit-Script 1 "Drift | Adapters=$($stale.Count); Details=$details"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
