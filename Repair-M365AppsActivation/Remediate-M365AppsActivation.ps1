<#
.SYNOPSIS
  Remediation script for Microsoft 365 Apps subscription activation state.

.DESCRIPTION
  Moves broken or stale vNext license files of the signed-in user to a backup folder so Office requests a fresh license on the next start. Optionally resets the cached Office identity. Exits 0 when the license store is clean, 1 when no license file exists or a file cannot be moved.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$ExpectedProducts   = @()
$TokenMaxAgeDays    = 45
$EnableRemediation  = $true
$ResetIdentityCache = $false
$InventoryKey       = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Inventory\Office\16.0'
$ClickToRunKey      = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$LicenseRoot        = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses'
$BackupRoot         = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup\OfficeActivation'
$IdentityKey        = 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity'

$PackageName = 'M365AppsActivation'
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
function Get-OfficeInfo {
    $releaseIds = ''
    $version    = ''
    if (Test-Path -LiteralPath $InventoryKey) {
        $inventory  = Get-ItemProperty -LiteralPath $InventoryKey -ErrorAction SilentlyContinue
        $releaseIds = [string]$inventory.OfficeProductReleaseIds
        $version    = [string]$inventory.OfficePackageVersion
    }
    $products = @()
    if (-not [string]::IsNullOrWhiteSpace($releaseIds)) {
        $products = @($releaseIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    [pscustomobject]@{
        Product      = ($products -join ',')
        Version      = $version
        Subscription = (@($products | Where-Object { $_ -match 'O365|Microsoft365' }).Count -gt 0)
        Volume       = (@($products | Where-Object { $_ -match 'Volume$' }).Count -gt 0)
    }
}
function Get-LicenseState {
    $state = [pscustomobject]@{
        RootExists = $false
        Files      = @()
        Total      = 0
        Empty      = 0
        Stale      = 0
        NewestDays = -1
    }
    if (-not (Test-Path -LiteralPath $LicenseRoot -PathType Container)) { return $state }
    $state.RootExists = $true
    $files   = @()
    $folders = @(Get-ChildItem -LiteralPath $LicenseRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[0-9]+$' })
    foreach ($folder in $folders) {
        $files += @(Get-ChildItem -LiteralPath $folder.FullName -File -Force -ErrorAction SilentlyContinue)
    }
    if ($files.Count -eq 0) {
        $files = @(Get-ChildItem -LiteralPath $LicenseRoot -File -Force -ErrorAction SilentlyContinue)
    }
    $limit       = (Get-Date).AddDays(-$TokenMaxAgeDays)
    $state.Files = $files
    $state.Total = $files.Count
    $state.Empty = @($files | Where-Object { $_.Length -eq 0 }).Count
    $state.Stale = @($files | Where-Object { $_.Length -gt 0 -and $_.LastWriteTime -lt $limit }).Count
    if ($files.Count -gt 0) {
        $newest = ($files | Sort-Object LastWriteTime -Descending)[0]
        $state.NewestDays = [int]((Get-Date) - $newest.LastWriteTime).TotalDays
    }
    $state
}
function Backup-LicenseFiles {
    $result = [pscustomobject]@{ Moved = 0; Failed = 0; Backup = '' }
    $state  = Get-LicenseState
    if ($state.Total -eq 0) { return $result }

    $backup = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $backup -Force -ErrorAction Stop | Out-Null
    $result.Backup = $backup
    foreach ($file in $state.Files) {
        $relative = $file.FullName.Substring($LicenseRoot.Length).TrimStart('\')
        $target   = Join-Path $backup $relative
        $parent   = Split-Path -Parent $target
        try {
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
            Move-Item -LiteralPath $file.FullName -Destination $target -Force -ErrorAction Stop
            $result.Moved++
        }
        catch {
            $result.Failed++
            Write-IRTLog ('MoveFailed | File={0}; HResult={1}' -f $file.Name, $_.Exception.HResult) 'ERROR'
        }
    }
    $result
}
function Reset-IdentityCache {
    $result = [pscustomobject]@{ Exported = $false; Removed = $false }
    if (-not (Test-Path -LiteralPath $IdentityKey)) { return $result }

    $backup = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $backup -Force -ErrorAction Stop | Out-Null
    $file = Join-Path $backup 'Office-Identity.reg'
    & reg.exe export 'HKCU\Software\Microsoft\Office\16.0\Common\Identity' $file /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Identity export failed with exit code $LASTEXITCODE" }
    $result.Exported = $true
    Remove-Item -LiteralPath $IdentityKey -Recurse -Force -ErrorAction Stop
    $result.Removed = $true
    $result
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($identity -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) { Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User' }
    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $office = Get-OfficeInfo
    if ([string]::IsNullOrWhiteSpace($office.Product)) { Exit-Script 0 'NotApplicable | Office=NotInstalled' }
    if ($office.Volume) { Exit-Script 0 "NotApplicable | Product=$($office.Product); Activation=VolumeLicense" }
    if (-not $office.Subscription) { Exit-Script 0 "NotApplicable | Product=$($office.Product); Activation=Perpetual" }
    if ($ExpectedProducts.Count -gt 0) {
        $ids   = @($office.Product -split ',')
        $match = @($ExpectedProducts | Where-Object { $ids -contains $_ })
        if ($match.Count -eq 0) { Exit-Script 0 "NotApplicable | Product=$($office.Product); Expected=NotInstalled" }
    }

    $config = Get-ItemProperty -LiteralPath $ClickToRunKey -ErrorAction SilentlyContinue
    if ($null -ne $config -and [string]$config.SharedComputerLicensing -eq '1') {
        Exit-Script 0 "NotApplicable | Product=$($office.Product); SCA=Enabled"
    }

    $state = Get-LicenseState
    $healthy = $state.Total -gt 0 -and $state.Empty -eq 0 -and $state.Stale -lt $state.Total
    if ($healthy) { Exit-Script 0 "Healthy | Product=$($office.Product); Tokens=$($state.Total); NewestDays=$($state.NewestDays)" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Product=$($office.Product); Tokens=$($state.Total); Empty=$($state.Empty); EnableRemediation=Disabled" }

    $result = Backup-LicenseFiles
    $moved  = $result.Moved
    $failed = $result.Failed
    if ($moved -gt 0) { Write-IRTLog "LicenseFilesMoved | Count=$moved; Backup=$($result.Backup)" }

    $identityReset = $false
    if ($ResetIdentityCache -and $failed -eq 0) {
        $resetResult   = Reset-IdentityCache
        $identityReset = $resetResult.Removed
        if ($identityReset) { Write-IRTLog 'IdentityCacheReset | Backup=Office-Identity.reg' }
    }

    $after = Get-LicenseState
    if ($after.Empty -gt 0) { Exit-Script 1 "Failed | Tokens=$($after.Total); Empty=$($after.Empty); Moved=$moved" }
    if ($failed -gt 0) { Exit-Script 1 "Failed | MoveFailed=$failed; Moved=$moved" }
    if ($after.Total -eq 0) {
        if ($identityReset) { Exit-Script 0 "Fixed | Tokens=0; Moved=$moved; Identity=Reset; Action=SignInToOffice" }
        if ($moved -gt 0) { Exit-Script 0 "Fixed | Tokens=0; Moved=$moved; Action=OpenOfficeToReactivate" }
        Exit-Script 1 "Pending | License=Missing; Moved=0; Action=SignInToOffice"
    }
    Exit-Script 0 "Fixed | Tokens=$($after.Total); Moved=$moved; NewestDays=$($after.NewestDays)"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
