<#
.SYNOPSIS
  Detection script for Explorer thumbnail previews.

.DESCRIPTION
  Reads the thumbnail setting of the signed-in user and the thumbnail policy under the user policy key.
  Exits 1 when File Explorer shows icons only, 0 when thumbnails are enabled or the script has no user profile to read.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedIconsOnly = 0

$PackageName = 'ExplorerThumbnails'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
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

function Get-RegistryDword { param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return [int]$item.$Name
}

try {
    $ErrorActionPreference = 'Stop'
    $advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $userPolicyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'

    if (-not (Test-Path -LiteralPath $advancedKey)) { Exit-Script 0 'NotApplicable | Reason=NoLoadedUserProfile' }

    $iconsOnly = Get-RegistryDword -Path $advancedKey -Name 'IconsOnly'
    $userPolicy = Get-RegistryDword -Path $userPolicyKey -Name 'DisableThumbnails'

    if ($null -eq $iconsOnly) { $iconsOnly = 0 }
    if ($null -eq $userPolicy) { $userPolicy = 0 }

    $details = 'IconsOnly={0}; UserPolicy={1}' -f $iconsOnly, $userPolicy

    if ($userPolicy -eq 1) {
        Exit-Script 1 "PolicyBlocked | $details; Location=User; Thumbnails=Off"
    }
    if ($iconsOnly -ne $ExpectedIconsOnly) {
        Exit-Script 1 "Drift | $details; Thumbnails=Off; Source=UserSetting"
    }
    Exit-Script 0 "Healthy | $details; Thumbnails=On"
}
catch { Exit-Script 1 "Failed | Reason=$($_.Exception.Message)" }
