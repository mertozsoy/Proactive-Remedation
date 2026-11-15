<#
.SYNOPSIS
  Detection script for duplicate and obsolete VPN connections.

.DESCRIPTION
  Reads the VPN connections in the signed-in user's phone book. Flags connections that are named in the obsolete name or gateway list and connections that are a copy of another entry. Exits 1 if an entry can be removed, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ObsoleteNames           = @()
$ObsoleteServerAddresses = @()
$ProtectedNames          = @()
$CopySuffixPatterns      = @(' \(\d+\)$', ' - Copy$', ' - Kopya$', ' Copy$', ' Kopya$')

$PackageName = 'StaleVpnConnections'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-BaseName { param([string]$Name)
    $value = $Name.Trim()
    foreach ($pattern in $CopySuffixPatterns) {
        $stripped = [regex]::Replace($value, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim()
        if ($stripped -ne $value -and $stripped.Length -gt 0) { return $stripped }
    }
    return $value
}

function Get-StaleVpnEntry { param([object[]]$Connections)
    $names   = @($Connections | ForEach-Object { $_.Name })
    $entries = @()
    foreach ($conn in $Connections) {
        if ($ProtectedNames -contains $conn.Name) { continue }
        $reason = $null
        if ($ObsoleteNames -contains $conn.Name) { $reason = 'ListedObsolete' }
        elseif ($ObsoleteServerAddresses -contains $conn.ServerAddress) { $reason = 'RetiredGateway' }
        else {
            $base = Get-BaseName -Name $conn.Name
            if ($base -ne $conn.Name -and $names -contains $base) { $reason = 'DuplicateName' }
        }
        if ($reason) {
            $entries += [pscustomobject]@{
                Name          = $conn.Name
                Reason        = $reason
                ServerAddress = $conn.ServerAddress
                Status        = $conn.ConnectionStatus
            }
        }
    }
    return $entries
}

function Format-NameList { param([string[]]$Names)
    $listed = @($Names | Select-Object -First 8)
    $text   = ($listed -join ',')
    if ($Names.Count -gt $listed.Count) { $text = $text + '+more' }
    return $text
}

try {
    if (-not (Get-Command -Name Get-VpnConnection -ErrorAction SilentlyContinue)) {
        Exit-Script 0 'NotApplicable | VpnClientModule=Missing'
    }

    $connections = @(Get-VpnConnection -ErrorAction SilentlyContinue)
    if ($connections.Count -eq 0) { Exit-Script 0 'NotApplicable | VpnConnections=0' }

    $entries = @(Get-StaleVpnEntry -Connections $connections)
    if ($entries.Count -eq 0) {
        Exit-Script 0 "Healthy | VpnConnections=$($connections.Count); Duplicate=0; Obsolete=0"
    }

    $names    = @($entries | ForEach-Object { $_.Name })
    $implicit = @($entries | Where-Object { $_.Reason -eq 'DuplicateName' })
    if ($entries.Count -ge $connections.Count -and $implicit.Count -gt 0) {
        Exit-Script 1 "Drift | VpnConnections=$($connections.Count); Remove=$($entries.Count); Reason=AllConnectionsMatch"
    }

    $detail = (@($entries | ForEach-Object { '{0}={1}' -f $_.Name, $_.Reason }) -join '; ')
    Exit-Script 1 "Stale | VpnConnections=$($connections.Count); Remove=$($entries.Count); Names=$(Format-NameList -Names $names); Detail=$detail"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
