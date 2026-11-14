<#
.SYNOPSIS
  Remediation script for mapped network drives.

.DESCRIPTION
  Removes stale mappings and maps the expected drives again as persistent drives with the signed-in user's own credentials. Exits 0 if every reachable drive is mapped, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$DriveMaps = @(
    @{ Letter = 'S'; Path = '\\fs01.contoso.local\Shared' }
)
$PortTimeoutMs = 3000

$PackageName = 'NetworkDrives'
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

function Test-SmbPort { param([string]$Server)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($Server, 445, $null, $null)
        return ($pending.AsyncWaitHandle.WaitOne($PortTimeoutMs) -and $client.Connected)
    }
    catch { return $false }
    finally { $client.Close() }
}

function Get-DriveState {
    $disks = @(Get-CimInstance Win32_LogicalDisk)
    foreach ($map in $DriveMaps) {
        $letter = $map.Letter.TrimEnd(':').ToUpper()
        $disk   = $disks | Where-Object { $_.DeviceID -eq "${letter}:" }
        $saved  = (Get-ItemProperty -LiteralPath "HKCU:\Network\$letter" -ErrorAction SilentlyContinue).RemotePath
        $server = ($map.Path -split '\\')[2]

        if ($disk -and $disk.DriveType -ne 4) { $state = 'LetterInUse' }
        elseif ($disk -and $disk.ProviderName -eq $map.Path -and (Test-Path -LiteralPath "${letter}:\")) { $state = 'OK' }
        elseif (-not (Test-SmbPort -Server $server)) { $state = 'Offline' }
        elseif ($disk -and $disk.ProviderName -ne $map.Path) { $state = 'WrongPath' }
        elseif ($saved -and $saved -ne $map.Path) { $state = 'WrongPath' }
        elseif ($disk -or $saved) { $state = 'Disconnected' }
        else { $state = 'Missing' }
        [pscustomobject]@{ Letter = $letter; Path = $map.Path; State = $state }
    }
}

try {
    if (-not $DriveMaps -or $DriveMaps.Count -eq 0) { Exit-Script 0 'NotApplicable | DriveMaps=None' }

    $network = New-Object -ComObject WScript.Network
    $actions = @()
    foreach ($drive in @(Get-DriveState | Where-Object { $_.State -in 'Missing', 'Disconnected', 'WrongPath' })) {
        $name = "$($drive.Letter):"
        try {
            if ($drive.State -ne 'Missing') {
                try { $network.RemoveNetworkDrive($name, $true, $true) } catch { Write-IRTLog "Remove ${name}: $($_.Exception.Message)" 'WARN' }
            }
            $network.MapNetworkDrive($name, $drive.Path, $true)
            $actions += "$($drive.Letter)=Mapped"
            Write-IRTLog "Mapped $name to $($drive.Path)"
        }
        catch {
            $actions += "$($drive.Letter)=Error"
            Write-IRTLog "Map ${name}: $($_.Exception.Message)" 'ERROR'
        }
    }

    $states  = @(Get-DriveState)
    $summary = (@($states | ForEach-Object { '{0}={1}' -f $_.Letter, $_.State }) -join '; ')
    $left    = @($states | Where-Object { $_.State -in 'Missing', 'Disconnected', 'WrongPath' })
    if ($left.Count -eq 0) { Exit-Script 0 "Remediated | $summary; Actions=$($actions -join ',')" }
    Exit-Script 1 "Failed | $summary; Actions=$($actions -join ',')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
