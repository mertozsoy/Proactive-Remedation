<#
.SYNOPSIS
  Detection script for camera and microphone access that the user switched off.

.DESCRIPTION
  Reads the per-user consent store for webcam and microphone and reports every scope where access is Deny. Exits 1 if a value the script can repair is Deny, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$Capabilities     = @('webcam', 'microphone')
$AppKeys          = @('MSTeams_8wekyb3d8bbwe')
$CheckDesktopApps = $true

$PackageName = 'CameraMicAccess'
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

$UserRoot    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
$MachineRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
$PolicyRoot  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
$PolicyNames = @{ webcam = 'LetAppsAccessCamera'; microphone = 'LetAppsAccessMicrophone' }

function Get-RegValue {
    param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return $item.$Name
}

function Get-AccessState {
    $state = @()
    foreach ($cap in $Capabilities) {
        $policy = Get-RegValue -Path $PolicyRoot -Name $PolicyNames[$cap]
        if ($policy -eq 1 -or $policy -eq 2) {
            $label = 'Allow'
            if ($policy -eq 2) { $label = 'Deny' }
            $state += [pscustomobject]@{ Name = $cap; Scope = 'Policy'; Value = $label }
            continue
        }

        $device = Get-RegValue -Path (Join-Path $MachineRoot $cap) -Name 'Value'
        if ($device -eq 'Deny') {
            $state += [pscustomobject]@{ Name = $cap; Scope = 'Device'; Value = 'Deny' }
            continue
        }

        $user = Get-RegValue -Path (Join-Path $UserRoot $cap) -Name 'Value'
        if ($user -eq 'Deny') {
            $state += [pscustomobject]@{ Name = $cap; Scope = 'User'; Value = 'Deny' }
        }

        if ($CheckDesktopApps) {
            $desktop = Get-RegValue -Path (Join-Path (Join-Path $UserRoot $cap) 'NonPackaged') -Name 'Value'
            if ($desktop -eq 'Deny') {
                $state += [pscustomobject]@{ Name = $cap; Scope = 'DesktopApps'; Value = 'Deny' }
            }
        }

        foreach ($appKey in $AppKeys) {
            $appValue = Get-RegValue -Path (Join-Path (Join-Path $UserRoot $cap) $appKey) -Name 'Value'
            if ($appValue -eq 'Deny') {
                $state += [pscustomobject]@{ Name = $cap; Scope = $appKey; Value = 'Deny' }
            }
        }
    }
    return $state
}

try {
    $states  = @(Get-AccessState)
    $off     = @($states | Where-Object { $_.Value -eq 'Deny' -and $_.Scope -ne 'Device' -and $_.Scope -ne 'Policy' })
    $blocked = @($states | Where-Object { $_.Value -eq 'Deny' -and ($_.Scope -eq 'Device' -or $_.Scope -eq 'Policy') })

    $blockedText = 'None'
    if ($blocked.Count -gt 0) {
        $blockedText = (@($blocked | ForEach-Object { '{0}/{1}' -f $_.Name, $_.Scope }) -join ',')
    }

    if ($off.Count -gt 0) {
        $offText = (@($off | ForEach-Object { '{0}/{1}' -f $_.Name, $_.Scope }) -join ',')
        Exit-Script 1 "Drift | Off=$offText; Blocked=$blockedText"
    }
    if ($blocked.Count -gt 0) {
        Exit-Script 0 "NotApplicable | Off=0; Blocked=$blockedText"
    }
    Exit-Script 0 'Healthy | Off=0; Blocked=None'
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
