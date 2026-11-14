<#
.SYNOPSIS
  Detection script for OneDrive Known Folder Move.

.DESCRIPTION
  Checks whether the folders covered by the KFMSilentOptIn policy are redirected into the work OneDrive folder of the signed-in user. Exits 1 if a folder is still local, 0 if all are redirected or the policy is not set.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$MaxAttempts = 3

$PackageName = 'OneDriveKfm'
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

try {
    $kfm = Get-KfmStatus
    if (-not $kfm.Policy) { Exit-Script 0 'NotApplicable | KfmPolicy=NotSet' }

    $attempts = [int](Get-ItemProperty -LiteralPath 'HKCU:\Software\IntuneRemediations\OneDriveKfm' -ErrorAction SilentlyContinue).Attempts
    $running  = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
    $summary  = 'SignedIn={0}; OneDriveRunning={1}; Attempts={2}/{3}' -f [bool]$kfm.Root, $running, $attempts, $MaxAttempts

    if ($kfm.Local.Count -eq 0) { Exit-Script 0 "Redirected | $summary" }
    if ($kfm.Blocked) { Exit-Script 1 "NotRedirected ($($kfm.Local -join ',')) | Blocker=DisablePersonalDirChange; $summary" }
    Exit-Script 1 "NotRedirected ($($kfm.Local -join ',')) | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
