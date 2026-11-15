<#
.SYNOPSIS
  Remediation script that turns camera and microphone app access back on for the signed-in user.

.DESCRIPTION
  Sets the per-user consent values for webcam and microphone to Allow, including the desktop apps bucket and the configured app keys. Exits 0 when every repairable value is Allow, 1 when a value is still Deny.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$Capabilities       = @('webcam', 'microphone')
$AppKeys            = @('MSTeams_8wekyb3d8bbwe')
$CheckDesktopApps   = $true
$EnableRemediation  = $true
$BackupConsentStore = $true

$PackageName = 'CameraMicAccess'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
$BackupDir   = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'
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

function Backup-ConsentKey {
    param([string]$Capability)
    if (-not $BackupConsentStore) { return }
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $fileName = 'ConsentStore_{0}_{1}.reg' -f $Capability, (Get-Date -Format 'yyyyMMdd_HHmmss')
    $filePath = Join-Path $BackupDir $fileName
    $regPath  = 'HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\' + $Capability
    & reg.exe export $regPath $filePath /y | Out-Null
    if (Test-Path -LiteralPath $filePath) { Write-IRTLog "Backup written: $filePath" }
    else { Write-IRTLog "Backup failed: $Capability" 'WARN' }
}

function Set-ConsentAllow {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    New-ItemProperty -LiteralPath $Path -Name 'Value' -Value 'Allow' -PropertyType String -Force -ErrorAction Stop | Out-Null
    return $true
}

try {
    $states = @(Get-AccessState)
    $targets = @($states | Where-Object { $_.Value -eq 'Deny' -and $_.Scope -ne 'Device' -and $_.Scope -ne 'Policy' })

    $blocked = @($states | Where-Object { $_.Value -eq 'Deny' -and ($_.Scope -eq 'Device' -or $_.Scope -eq 'Policy') })
    $blockedText = 'None'
    if ($blocked.Count -gt 0) {
        $blockedText = (@($blocked | ForEach-Object { '{0}/{1}' -f $_.Name, $_.Scope }) -join ',')
    }

    if ($targets.Count -eq 0) {
        Exit-Script 0 "Healthy | Off=0; Blocked=$blockedText"
    }
    if (-not $EnableRemediation) {
        Exit-Script 0 "ReportOnly | Off=$($targets.Count); Blocked=$blockedText"
    }

    $backedUp = @{}
    $set      = @()
    foreach ($item in $targets) {
        $capability = $item.Name
        if (-not $backedUp.ContainsKey($capability)) {
            Backup-ConsentKey -Capability $capability
            $backedUp[$capability] = $true
        }

        $keyPath = Join-Path $UserRoot $capability
        if ($item.Scope -ne 'User') { $keyPath = Join-Path $keyPath $item.Scope }
        $label = '{0}/{1}' -f $capability, $item.Scope

        try {
            if (Set-ConsentAllow -Path $keyPath) {
                Write-IRTLog "Allow set: $label"
                $set += $label
            }
            else {
                Write-IRTLog "Key missing: $label" 'WARN'
            }
        }
        catch {
            Write-IRTLog "Set failed: $label ($($_.Exception.Message))" 'ERROR'
        }
    }

    $after      = @(Get-AccessState)
    $left       = @($after | Where-Object { $_.Value -eq 'Deny' -and $_.Scope -ne 'Device' -and $_.Scope -ne 'Policy' })
    $blockedNow = @($after | Where-Object { $_.Value -eq 'Deny' -and ($_.Scope -eq 'Device' -or $_.Scope -eq 'Policy') })
    if ($blockedNow.Count -gt 0) {
        $blockedText = (@($blockedNow | ForEach-Object { '{0}/{1}' -f $_.Name, $_.Scope }) -join ',')
    }

    $setText = (@($set) -join ',')
    if ($left.Count -gt 0) {
        $leftText = (@($left | ForEach-Object { '{0}/{1}' -f $_.Name, $_.Scope }) -join ',')
        Exit-Script 1 "Failed | Set=$setText; Remaining=$leftText; Blocked=$blockedText"
    }
    Exit-Script 0 "Fixed | Set=$setText; Blocked=$blockedText; AppRestart=Required"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
