<#
.SYNOPSIS
  Remediation script for the Windows Spotlight "Learn about this picture" desktop icon.

.DESCRIPTION
  Hides the Spotlight desktop icon for the current user and refreshes the desktop. Exits 0 when the value is set and verified, 1 on failure.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$SpotlightIconId = '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}'

$PackageName = 'SpotlightDesktopIcon'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Update-DesktopView {
    $signature = '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);'
    try {
        if (-not ('IRT.ShellNotify' -as [type])) { Add-Type -Namespace 'IRT' -Name 'ShellNotify' -MemberDefinition $signature -ErrorAction Stop }
        [IRT.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
        return 'Refreshed'
    } catch { return 'RefreshSkipped' }
}

try {
    $panelKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
    if (-not (Test-Path -LiteralPath $panelKey)) { New-Item -Path $panelKey -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -Path $panelKey -Name $SpotlightIconId -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
    Write-IRTLog "Set $SpotlightIconId=1"

    $refresh = Update-DesktopView
    $value = (Get-ItemProperty -Path $panelKey -Name $SpotlightIconId -ErrorAction SilentlyContinue).$SpotlightIconId
    if ($value -eq 1) { Exit-Script 0 "Remediated | SpotlightIcon=Hidden; Desktop=$refresh" }
    Exit-Script 1 "Failed | SpotlightIcon value not verified; Desktop=$refresh"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
