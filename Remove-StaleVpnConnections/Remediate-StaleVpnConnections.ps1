<#
.SYNOPSIS
  Remediation script for duplicate and obsolete VPN connections.

.DESCRIPTION
  Removes the VPN connections that the detection script flags in the signed-in user's phone book. Backs up the phone book file first and leaves a connected entry alone. Exits 0 if no flagged entry is left, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$EnableRemediation       = $true
$ObsoleteNames           = @()
$ObsoleteServerAddresses = @()
$ProtectedNames          = @()
$CopySuffixPatterns      = @(' \(\d+\)$', ' - Copy$', ' - Kopya$', ' Copy$', ' Kopya$')

$PackageName = 'StaleVpnConnections'
$Phase       = 'Remediate'
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

function Backup-PhoneBook {
    $phoneBook = Join-Path $env:APPDATA 'Microsoft\Network\Connections\Pbk\rasphone.pbk'
    if (-not (Test-Path -LiteralPath $phoneBook)) { return 'None' }
    $backupDir = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $backupFile = Join-Path $backupDir ('rasphone_{0}.pbk' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Copy-Item -LiteralPath $phoneBook -Destination $backupFile -Force -ErrorAction Stop
    return (Split-Path -Leaf $backupFile)
}

try {
    if (-not (Get-Command -Name Get-VpnConnection -ErrorAction SilentlyContinue)) {
        Exit-Script 0 'NotApplicable | VpnClientModule=Missing'
    }

    $connections = @(Get-VpnConnection -ErrorAction SilentlyContinue)
    if ($connections.Count -eq 0) { Exit-Script 0 "Healthy | VpnConnections=0" }

    $targets = @(Get-StaleVpnEntry -Connections $connections)
    if ($targets.Count -eq 0) { Exit-Script 0 "Healthy | VpnConnections=$($connections.Count); Remove=0" }

    $targetNames = @($targets | ForEach-Object { $_.Name })
    $implicit    = @($targets | Where-Object { $_.Reason -eq 'DuplicateName' })
    if ($targets.Count -ge $connections.Count -and $implicit.Count -gt 0) {
        Exit-Script 1 "Skipped | Reason=AllConnectionsMatch; VpnConnections=$($connections.Count)"
    }
    if ($EnableRemediation -eq $false) {
        Exit-Script 0 "ReportOnly | Remove=$($targets.Count); Names=$(Format-NameList -Names $targetNames)"
    }

    $backup = 'None'
    try { $backup = Backup-PhoneBook } catch { Write-IRTLog "Backup: $($_.Exception.Message)" 'WARN' }

    $removed = @()
    $skipped = @()
    foreach ($entry in $targets) {
        if ($entry.Status -eq 'Connected') {
            $skipped += $entry.Name
            Write-IRTLog "Skip connected entry $($entry.Name)" 'WARN'
            continue
        }
        try {
            Remove-VpnConnection -Name $entry.Name -Force -ErrorAction Stop
            $removed += $entry.Name
            Write-IRTLog "Removed $($entry.Name) ($($entry.Reason))"
        }
        catch {
            $skipped += $entry.Name
            Write-IRTLog "Remove $($entry.Name): $($_.Exception.Message)" 'ERROR'
        }
    }

    $remainingNames = @(Get-VpnConnection -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $left           = @($targets | Where-Object { $remainingNames -contains $_.Name })

    if ($left.Count -eq 0) {
        Exit-Script 0 "Fixed | Removed=$($removed.Count); Skipped=$($skipped.Count); Names=$(Format-NameList -Names $removed); Backup=$backup"
    }
    Exit-Script 1 "Partial | Removed=$($removed.Count); Left=$($left.Count); Skipped=$($skipped.Count); Names=$(Format-NameList -Names @($left | ForEach-Object { $_.Name })); Backup=$backup"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
