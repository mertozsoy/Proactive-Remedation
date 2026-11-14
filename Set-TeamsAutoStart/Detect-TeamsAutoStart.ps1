<#
.SYNOPSIS
  Detection script for the new Teams autostart startup task.

.DESCRIPTION
  Reads the TeamsTfwStartupTask state for the signed-in user and checks whether startup tasks are blocked by policy. Exits 1 if Teams autostart is off, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedState         = 2
$TeamsPackageName      = 'MSTeams'
$TeamsFamilyName       = 'MSTeams_8wekyb3d8bbwe'
$StartupTaskId         = 'TeamsTfwStartupTask'
$StartupPolicyKey      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$StartupPolicyValues   = @('EnableFullTrustStartupTasks', 'EnableUwpStartupTasks', 'SupportFullTrustStartupTasks', 'SupportUwpStartupTasks')
$TeamsLocalPackage     = Join-Path $env:LOCALAPPDATA "Packages\$TeamsFamilyName"
$StartupTaskRoot       = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$TeamsFamilyName\$StartupTaskId"

$PackageName = 'TeamsAutoStart'
$Phase       = 'Detect'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-StartupPolicyBlock {
    $properties = Get-ItemProperty -LiteralPath $StartupPolicyKey -ErrorAction SilentlyContinue
    if ($null -eq $properties) { return '' }
    foreach ($valueName in $StartupPolicyValues) {
        $property = $properties.PSObject.Properties[$valueName]
        if ($null -eq $property) { continue }
        if ([int]$property.Value -eq 0) { return $valueName }
    }
    return ''
}

function Get-StartupStateName {
    param([int]$State)
    switch ($State) {
        0 { return 'Disabled' }
        1 { return 'DisabledByUser' }
        2 { return 'EnabledByUser' }
        3 { return 'DisabledByPolicy' }
        4 { return 'EnabledByPolicy' }
        default { return "Unknown$State" }
    }
}

try {
    $ErrorActionPreference = 'Stop'

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }

    $teams = @(Get-AppxPackage -Name $TeamsPackageName -ErrorAction SilentlyContinue)
    if ($teams.Count -eq 0) { Exit-Script 0 'NotApplicable | NewTeams=NotInstalled' }

    $policyBlock = Get-StartupPolicyBlock
    if ($policyBlock) {
        Exit-Script 0 "NotApplicable | Reason=StartupTasksBlockedByPolicy; Value=$policyBlock"
    }

    $stateValue = (Get-ItemProperty -LiteralPath $StartupTaskRoot -Name 'State' -ErrorAction SilentlyContinue).State
    if ($null -eq $stateValue) {
        if (-not (Test-Path -LiteralPath $TeamsLocalPackage)) {
            Exit-Script 0 'Skipped | StartupTask=NotRegistered; FirstLaunch=NotDone'
        }
        Exit-Script 1 'Drift | StartupTask=Missing; Expected=EnabledByUser'
    }

    $state = [int]$stateValue
    $stateName = Get-StartupStateName -State $state

    if ($state -eq 3) {
        Exit-Script 0 "NotApplicable | Reason=StartupTaskDisabledByPolicy; State=$stateName"
    }
    if ($state -eq $ExpectedState -or $state -eq 4) {
        Exit-Script 0 "Healthy | StartupTask=$stateName; AutoStart=On"
    }

    Exit-Script 1 "Drift | StartupTask=$stateName; Expected=EnabledByUser"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
