<#
.SYNOPSIS
  Remediation script for shared computer activation licensing in Microsoft 365 Apps.

.DESCRIPTION
  Recreates a missing licensing token folder, moves unusable licensing tokens of the signed-in user to a backup folder and verifies the cache. Exits 0 when the cache is clean, 1 when tokens stay unusable or a new token is still required.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$OfficeVersion     = '16.0'
$TokenMaxAgeDays   = 25
$ResetTokenCache   = $true
$CreateTokenFolder = $true
$ClickToRunKey     = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

$PackageName = 'SharedComputerActivation'
$Phase       = 'Remediate'
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
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}
function Get-TokenFolder { param($Config)
    $override     = [string]$Config.SCLCacheOverride
    $overridePath = [string]$Config.SCLCacheOverrideDirectory
    if ($override -eq '1' -and -not [string]::IsNullOrWhiteSpace($overridePath)) { return $overridePath }
    Join-Path $env:LOCALAPPDATA "Microsoft\Office\$OfficeVersion\Licensing"
}
function Get-TokenState { param([string]$Folder)
    $exists = Test-Path -LiteralPath $Folder -PathType Container
    $files  = @()
    if ($exists) { $files = @(Get-ChildItem -LiteralPath $Folder -File -Force -ErrorAction SilentlyContinue) }
    $valid    = @($files | Where-Object { $_.Length -gt 0 })
    $limit    = (Get-Date).AddDays(-$TokenMaxAgeDays)
    $unusable = @($files | Where-Object { $_.Length -eq 0 -or $_.LastWriteTime -lt $limit })
    $age      = 0
    if ($valid.Count -gt 0) {
        $newest = ($valid | Sort-Object LastWriteTime -Descending)[0]
        $age    = [int]((Get-Date) - $newest.LastWriteTime).TotalDays
    }
    [pscustomobject]@{ Folder = $Folder; Exists = $exists; Total = $files.Count; Unusable = $unusable.Count; AgeDays = $age }
}
function Clear-TokenCache { param([string]$Folder)
    $limit  = (Get-Date).AddDays(-$TokenMaxAgeDays)
    $target = @(Get-ChildItem -LiteralPath $Folder -File -Force -ErrorAction Stop | Where-Object { $_.Length -eq 0 -or $_.LastWriteTime -lt $limit })
    $result = [pscustomobject]@{ Moved = 0; Failed = 0; Backup = '' }
    if ($target.Count -eq 0) { return $result }

    $backup = Join-Path $env:LOCALAPPDATA ('IntuneRemediations\Backup\OfficeLicensing\{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force -ErrorAction Stop | Out-Null
    $result.Backup = $backup
    foreach ($file in $target) {
        try {
            Move-Item -LiteralPath $file.FullName -Destination (Join-Path $backup $file.Name) -Force -ErrorAction Stop
            $result.Moved++
        }
        catch {
            $result.Failed++
            Write-IRTLog ('MoveFailed | File={0}; HResult={1}' -f $file.Name, $_.Exception.HResult) 'ERROR'
        }
    }
    $result
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($identity -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User' }
    if (-not (Test-Path -LiteralPath $ClickToRunKey)) { Exit-Script 0 'NotApplicable | Office=NotInstalled' }
    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $config = Get-ItemProperty -LiteralPath $ClickToRunKey -ErrorAction Stop
    if ([string]$config.SharedComputerLicensing -ne '1') { Exit-Script 0 'NotApplicable | SCA=Disabled; Required=SharedComputerLicensing' }

    $folder = Get-TokenFolder -Config $config
    $cache  = 'Default'
    if ([string]$config.SCLCacheOverride -eq '1') { $cache = 'Override' }

    $created = $false
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        if (-not $CreateTokenFolder) { Exit-Script 1 "Failed | Cache=$cache; Folder=Missing; CreateTokenFolder=Disabled" }
        if ($folder.StartsWith('\\')) { Exit-Script 1 "Failed | Cache=$cache; Folder=Missing; Action=FixTokenShare" }
        New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null
        $created = $true
        Write-IRTLog "FolderCreated | Path=$folder"
    }

    $moved  = 0
    $failed = 0
    if ($ResetTokenCache) {
        $result = Clear-TokenCache -Folder $folder
        $moved  = $result.Moved
        $failed = $result.Failed
        if ($moved -gt 0) { Write-IRTLog "TokensMoved | Count=$moved; Backup=$($result.Backup)" }
    }

    $after = Get-TokenState -Folder $folder
    if ($after.Unusable -gt 0) { Exit-Script 1 "Failed | Cache=$cache; Unusable=$($after.Unusable); Moved=$moved; Action=CloseOfficeApps" }
    if ($failed -gt 0) { Exit-Script 1 "Failed | Cache=$cache; MoveFailed=$failed; Moved=$moved" }
    if ($after.Total -eq 0) { Exit-Script 1 "Pending | Cache=$cache; Tokens=0; Moved=$moved; Action=OpenOfficeAndSignIn" }
    if ($moved -gt 0 -or $created) { Exit-Script 0 "Fixed | Cache=$cache; Tokens=$($after.Total); Moved=$moved; NewestDays=$($after.AgeDays)" }
    Exit-Script 0 "Healthy | Cache=$cache; Tokens=$($after.Total); NewestDays=$($after.AgeDays)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
