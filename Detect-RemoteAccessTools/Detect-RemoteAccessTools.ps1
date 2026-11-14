<#
.SYNOPSIS
  Detection script for unapproved remote access tools.

.DESCRIPTION
  Looks for installed, running or service based remote access tools such as TeamViewer and AnyDesk. Approved tools go in $AllowList. Report only. Exits 1 when a tool is found.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowList = @()

$Patterns = [ordered]@{
    'AnyDesk'              = 'AnyDesk'
    'TeamViewer'           = 'TeamViewer'
    'UltraViewer'          = 'UltraViewer'
    'RustDesk'             = 'RustDesk'
    'Splashtop'            = 'Splashtop|SRServer|SRManager'
    'ScreenConnect'        = 'ScreenConnect|ConnectWise Control'
    'Supremo'              = 'Supremo'
    'RemotePC'             = 'RemotePC'
    'Ammyy'                = 'Ammyy|AA_v3'
    'LogMeIn'              = 'LogMeIn|LMIGuardian'
    'ChromeRemoteDesktop'  = 'Chrome Remote Desktop|remoting_host'
    'DWService'            = 'DWAgent|DWService'
    'AeroAdmin'            = 'AeroAdmin'
    'NoMachine'            = 'NoMachine|nxservice'
    'Radmin'               = 'Radmin|rserver3'
    'TightVNC/UltraVNC'    = 'TightVNC|UltraVNC|RealVNC|tvnserver|winvnc|vncserver'
    'Zoho Assist'          = 'Zoho Assist|ZA_Connect'
    'GoToAssist'           = 'GoToAssist|GoTo Resolve'
    'Atera'                = 'AteraAgent'
    'MeshCentral'          = 'MeshAgent|MeshCentral'
}

$PackageName = 'RemoteAccessTools'
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

function Get-UninstallNames {
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($p in $paths) { Get-ItemProperty $p -ErrorAction SilentlyContinue | ForEach-Object { if ($_.DisplayName) { "M:$($_.DisplayName)" } } }

    $mounted = @()
    foreach ($prof in (Get-CimInstance Win32_UserProfile -Filter 'Special=False')) {
        $hive = "Registry::HKEY_USERS\$($prof.SID)"
        if (-not (Test-Path $hive)) {
            $dat = Join-Path $prof.LocalPath 'NTUSER.DAT'
            if (Test-Path $dat) {
                & reg.exe load "HKU\IRT_$($prof.SID)" "$dat" 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { $hive = "Registry::HKEY_USERS\IRT_$($prof.SID)"; $mounted += "HKU\IRT_$($prof.SID)" } else { continue }
            } else { continue }
        }
        Get-ItemProperty "$hive\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            ForEach-Object { if ($_.DisplayName) { "U($(Split-Path $prof.LocalPath -Leaf)):$($_.DisplayName)" } }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    foreach ($m in $mounted) { & reg.exe unload $m 2>$null | Out-Null }
}

try {
    $inventory = @()
    $inventory += Get-UninstallNames
    $inventory += Get-Process -ErrorAction SilentlyContinue | ForEach-Object { "P:$($_.ProcessName)" }
    $inventory += Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object { "S:$($_.Name)|$($_.DisplayName)" }

    $found = @{}
    foreach ($tool in $Patterns.Keys) {
        if ($AllowList | Where-Object { $tool -match $_ }) { continue }
        $hits = $inventory | Where-Object { $_ -match $Patterns[$tool] } | Select-Object -Unique -First 3
        if ($hits) { $found[$tool] = ($hits -join ' / ') }
    }

    if ($found.Count) {
        $txt = ($found.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) [$($_.Value)]" }) -join ' ; '
        Exit-Script 1 "Found=$($found.Count) | $txt"
    }
    Exit-Script 0 'None found'
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
