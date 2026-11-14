<#
.SYNOPSIS
  Detection script for a missing Cisco Secure Client VPN profile.

.DESCRIPTION
  Checks the configured profile file and its basic XML structure. Exits 1 when missing or invalid, 0 when present or not applicable. Does not compare existing profiles with a baseline.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProfileFileName = 'CorporateVpn.xml'
$VpnServiceNames = @('vpnagent', 'csc_vpnagent')
$MaxProfileBytes = 1048576

$PackageName = 'CiscoVpnProfile'
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
function Assert-SafePath { param([string]$Path)
    $current = [System.IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'ReparsePointNotAllowed' }
        }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
}
function Test-ProfileXml { param([byte[]]$Bytes)
    $stream = $null
    $reader = $null
    try {
        if ($Bytes.Length -eq 0 -or $Bytes.Length -gt $MaxProfileBytes) { return $false }
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = $MaxProfileBytes
        $stream = [System.IO.MemoryStream]::new($Bytes, $false)
        $reader = [System.Xml.XmlReader]::Create($stream, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
        if ($document.DocumentElement.LocalName -ne 'AnyConnectProfile') { return $false }
        $hosts = $document.SelectNodes('/*[local-name()="AnyConnectProfile"]/*[local-name()="ServerList"]/*[local-name()="HostEntry"]/*[local-name()="HostAddress"]')
        foreach ($hostAddress in $hosts) {
            if (-not [string]::IsNullOrWhiteSpace($hostAddress.InnerText)) { return $true }
        }
        return $false
    }
    catch { return $false }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if ($ProfileFileName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}\.xml$') {
        Exit-Script 1 'Failed | Reason=InvalidProfileFileName'
    }
    $clientRoot = Join-Path $env:ProgramData 'Cisco\Cisco Secure Client'
    $services = @(Get-Service -ErrorAction Stop | Where-Object { $VpnServiceNames -contains $_.Name })
    if ($services.Count -eq 0 -or -not (Test-Path -LiteralPath $clientRoot -PathType Container)) {
        Exit-Script 0 'NotApplicable | Reason=SecureClientVpnNotFound'
    }
    $profileDirectory = Join-Path $clientRoot 'VPN\Profile'
    $profilePath = Join-Path $profileDirectory $ProfileFileName
    Assert-SafePath -Path $profilePath
    if (-not (Test-Path -LiteralPath $profilePath)) { Exit-Script 1 'Drift | Profile=Missing; Action=Restore' }
    $item = Get-Item -LiteralPath $profilePath -Force
    if ($item.PSIsContainer -or $item.Length -gt $MaxProfileBytes) {
        Exit-Script 1 'Drift | Profile=Invalid; Action=ManualReview'
    }
    if (-not (Test-ProfileXml -Bytes ([System.IO.File]::ReadAllBytes($profilePath)))) {
        Exit-Script 1 'Drift | Profile=Invalid; Action=ManualReview'
    }
    Exit-Script 0 'Healthy | Profile=Present; Xml=Valid'
}
catch { Exit-Script 1 ('Error: Failed | Reason={0}' -f $_.Exception.GetType().Name) }
