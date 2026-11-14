<#
.SYNOPSIS
  Remediation script that registers missing inbox Store apps for the signed-in user.

.DESCRIPTION
  Registers staged inbox apps for the current user by package family name and checks the result. Exits 0 if all missing apps are registered, 1 on failure.

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
    $missing = @(Get-InboxAppState | Where-Object { $_.State -eq 'Missing' })
    if ($missing.Count -eq 0) { Exit-Script 0 'Healthy | Missing=None' }

    $failed = @()
    foreach ($app in $missing) {
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage $app.Family -ErrorAction Stop
            Write-IRTLog "Registered $($app.Family)"
        }
        catch {
            Write-IRTLog "Register failed for $($app.Family): $($_.Exception.Message)" 'ERROR'
            $failed += $app.Name
        }
    }

    $left = @(Get-InboxAppState | Where-Object { $_.State -eq 'Missing' })
    if ($left.Count -gt 0) { Exit-Script 1 "Failed | Remaining=$($left.Name -join ','); Errors=$($failed.Count)" }
    Exit-Script 0 "Registered | Apps=$($missing.Name -join ',')"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
