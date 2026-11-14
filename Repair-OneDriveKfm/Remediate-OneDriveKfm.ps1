<#
.SYNOPSIS
  Remediation script for OneDrive Known Folder Move.

.DESCRIPTION
  Restarts the OneDrive sync app gracefully so it evaluates the KFMSilentOptIn policy again, then checks the folder locations. Stops restarting after a set number of attempts. Exits 0 if the folders are redirected, 1 if not.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MaxAttempts = 3
$WaitSeconds = 90

$PackageName = 'OneDriveKfm'
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

function Get-KfmStatus {
    $policy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' -ErrorAction SilentlyContinue
    $status = [ordered]@{ Policy = [bool]$policy.KFMSilentOptIn; Root = $env:OneDriveCommercial; Local = @(); Blocked = $false }
    if (-not $status.Policy) { return [pscustomobject]$status }

    $selected = @{ Desktop = $policy.KFMSilentOptInDesktop; MyDocuments = $policy.KFMSilentOptInDocuments; MyPictures = $policy.KFMSilentOptInPictures }
    $explicit = @($selected.Values | Where-Object { $null -ne $_ }).Count -gt 0
    $explorer = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -ErrorAction SilentlyContinue
    $status.Blocked = ($explorer.DisablePersonalDirChange -eq 1)

    foreach ($folder in 'Desktop', 'MyDocuments', 'MyPictures') {
        if ($explicit -and $selected[$folder] -ne 1) { continue }
        $path = [Environment]::GetFolderPath($folder)
        if (-not $status.Root -or -not $path.StartsWith($status.Root, [StringComparison]::OrdinalIgnoreCase)) { $status.Local += $folder }
    }
    return [pscustomobject]$status
}

function Get-OneDriveExe {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe')
    )
    return $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

try {
    $kfm = Get-KfmStatus
    if (-not $kfm.Policy) { Exit-Script 0 'NotApplicable | KfmPolicy=NotSet' }
    if ($kfm.Local.Count -eq 0) { Exit-Script 0 'Redirected | Action=None' }
    if ($kfm.Blocked) { Exit-Script 1 "Blocked ($($kfm.Local -join ',')) | Blocker=DisablePersonalDirChange; Action=None" }

    $stateKey = 'HKCU:\Software\IntuneRemediations\OneDriveKfm'
    $attempts = [int](Get-ItemProperty -LiteralPath $stateKey -ErrorAction SilentlyContinue).Attempts
    if ($attempts -ge $MaxAttempts) { Exit-Script 1 "ManualCheck ($($kfm.Local -join ',')) | Attempts=$attempts/$MaxAttempts; Action=None" }

    $exe = Get-OneDriveExe
    if (-not $exe) { Exit-Script 1 'Failed | OneDriveExe=NotFound' }

    if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) {
        Start-Process -FilePath $exe -ArgumentList '/shutdown' -ErrorAction Stop
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Process -Name OneDrive -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    }
    Start-Process -FilePath $exe -ArgumentList '/background' -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $stateKey)) { New-Item -Path $stateKey -Force | Out-Null }
    $attempts++
    Set-ItemProperty -LiteralPath $stateKey -Name 'Attempts' -Value $attempts -Type DWord
    Write-IRTLog "OneDrive restarted, attempt $attempts of $MaxAttempts"

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do { Start-Sleep -Seconds 10; $kfm = Get-KfmStatus } while ($kfm.Local.Count -gt 0 -and (Get-Date) -lt $deadline)

    if ($kfm.Local.Count -eq 0) {
        Remove-ItemProperty -LiteralPath $stateKey -Name 'Attempts' -ErrorAction SilentlyContinue
        Exit-Script 0 "Redirected | Action=OneDriveRestarted; Attempts=$attempts/$MaxAttempts"
    }
    Exit-Script 1 "Pending ($($kfm.Local -join ',')) | Action=OneDriveRestarted; Attempts=$attempts/$MaxAttempts"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
