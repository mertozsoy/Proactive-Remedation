<#
.SYNOPSIS
  Detection script for inbox Store apps that are missing for the signed-in user.

.DESCRIPTION
  Checks whether Notepad, Snipping Tool, Calculator and Microsoft Store are registered for the current user. Exits 1 if an app is staged on the device but not registered for the user, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$InboxApps = @(
    'Microsoft.WindowsNotepad_8wekyb3d8bbwe'
    'Microsoft.ScreenSketch_8wekyb3d8bbwe'
    'Microsoft.WindowsCalculator_8wekyb3d8bbwe'
    'Microsoft.WindowsStore_8wekyb3d8bbwe'
)

$PackageName = 'InboxApps'
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

$AllUserStore = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'

function Get-InboxAppState {
    foreach ($family in $InboxApps) {
        $name      = $family.Split('_')[0]
        $publisher = $family.Split('_')[1]
        $installed = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.PackageFamilyName -eq $family }
        if ($installed) { $state = 'Registered' }
        elseif (Test-Path -LiteralPath (Join-Path $AllUserStore "Deprovisioned\$family")) { $state = 'Deprovisioned' }
        elseif (Get-ChildItem -LiteralPath (Join-Path $AllUserStore 'Applications') -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "${name}_*_$publisher" }) { $state = 'Missing' }
        else { $state = 'NotStaged' }
        [pscustomobject]@{ Family = $family; Name = $name; State = $state }
    }
}

try {
    $apps    = @(Get-InboxAppState)
    $missing = @($apps | Where-Object { $_.State -eq 'Missing' })
    $skipped = @($apps | Where-Object { $_.State -in 'Deprovisioned', 'NotStaged' })
    $summary = 'Missing={0}; Skipped={1}' -f ($(if ($missing) { $missing.Name -join ',' } else { 'None' })), ($(if ($skipped) { ($skipped | ForEach-Object { '{0}({1})' -f $_.Name, $_.State }) -join ',' } else { 'None' }))
    if ($missing.Count -gt 0) { Exit-Script 1 "MissingApps | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
