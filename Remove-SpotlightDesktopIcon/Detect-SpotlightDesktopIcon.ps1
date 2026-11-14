<#
.SYNOPSIS
  Detection script for the Windows Spotlight "Learn about this picture" desktop icon.

.DESCRIPTION
  Checks whether the Spotlight desktop icon is hidden for the current user. Exits 1 if the icon can still be shown, 0 if it is hidden or Spotlight on the desktop is turned off by policy.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$SpotlightIconId = '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}'

$PackageName = 'SpotlightDesktopIcon'
$Phase       = 'Detect'
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

try {
    $policy = Get-ItemProperty -Path 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' -ErrorAction SilentlyContinue
    if ($policy.DisableSpotlightCollectionOnDesktop -eq 1 -or $policy.DisableWindowsSpotlightFeatures -eq 1) {
        Exit-Script 0 'NotApplicable | SpotlightOnDesktop=DisabledByPolicy'
    }

    $panelKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
    $value = (Get-ItemProperty -Path $panelKey -Name $SpotlightIconId -ErrorAction SilentlyContinue).$SpotlightIconId

    if ($value -eq 1) { Exit-Script 0 'Compliant | SpotlightIcon=Hidden' }
    Exit-Script 1 ('NonCompliant | SpotlightIcon=Visible; Value={0}' -f ($(if ($null -ne $value) { $value } else { 'Missing' })))
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
