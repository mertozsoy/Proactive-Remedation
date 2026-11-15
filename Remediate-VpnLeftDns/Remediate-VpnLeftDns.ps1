<#
.SYNOPSIS
  Remediation script that removes static DNS servers left on physical adapters by a VPN client.

.DESCRIPTION
  Backs up the TCP/IP interface key, resets the DNS server addresses of every affected adapter to the DHCP-provided list, flushes the DNS cache and verifies the result. Exits 0 if the static value is gone, 1 otherwise.

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

$EnableRemediation = $true
$FlushDnsCache     = $true
$BackupFolder      = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'VpnLeftDns'
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

function Backup-InterfaceKey { param([string]$InterfaceGuid, [string]$SafeName, [int]$InterfaceIndex)
    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force -ErrorAction Stop | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $file  = Join-Path $BackupFolder ('Tcpip_{0}_{1}_{2}.reg' -f $SafeName, $InterfaceIndex, $stamp)
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    $keyName = $InterfaceGuid.Trim()
    if (-not $keyName.StartsWith('{')) { $keyName = '{' + $keyName + '}' }
    $keyPath = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $keyName
    & $regExe export $keyPath $file /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { return $null }
    $file
}

try {
    if (Test-VpnAdapterConnected) { Exit-Script 0 'NotApplicable | VpnActive=True' }

    $stale = @(Get-StaleDnsAdapter)
    if ($stale.Count -eq 0) { Exit-Script 0 "Healthy | DhcpAdapters=$script:EvaluatedAdapters; StaticDns=0" }

    $details = ($stale | ForEach-Object { '{0}={1}' -f $_.Name, ($_.Static -join '|') }) -join '; '
    if (-not $EnableRemediation) { Exit-Script 1 "Drift | Adapters=$($stale.Count); Details=$details; Remediation=Disabled" }

    $reset = @()
    foreach ($item in $stale) {
        $safeName = $item.Name -replace '[^A-Za-z0-9_-]', '_'
        $backup = Backup-InterfaceKey -InterfaceGuid $item.Guid -SafeName $safeName -InterfaceIndex $item.Index
        if (-not $backup) {
            Write-IRTLog "Backup failed for $($item.Name), adapter skipped" 'WARN'
            continue
        }
        Write-IRTLog "Backup written: $backup"
        try {
            Set-DnsClientServerAddress -InterfaceIndex $item.Index -ResetServerAddresses -ErrorAction Stop
            $reset += $item.Name
            Write-IRTLog "Static DNS reset on $($item.Name): $($item.Static -join ',')"
        }
        catch {
            Write-IRTLog "Reset failed on $($item.Name): $($_.Exception.Message)" 'WARN'
        }
    }

    if ($FlushDnsCache) {
        try { Clear-DnsClientCache -ErrorAction Stop }
        catch { Write-IRTLog 'DNS cache flush failed' 'WARN' }
    }

    $remaining = @(Get-StaleDnsAdapter)
    if ($remaining.Count -gt 0) {
        $left = ($remaining | ForEach-Object { $_.Name }) -join ','
        Exit-Script 1 "Failed | Remaining=$($remaining.Count); Adapters=$left"
    }

    $names = @($reset | Select-Object -Unique) -join ','
    Exit-Script 0 "Fixed | Adapters=$(@($reset | Select-Object -Unique).Count); Reset=$names; FlushDns=$FlushDnsCache"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
