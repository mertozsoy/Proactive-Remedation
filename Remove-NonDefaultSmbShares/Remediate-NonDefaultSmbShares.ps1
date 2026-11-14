<#
.SYNOPSIS
  Remediation script for non-default SMB shares on workstations.

.DESCRIPTION
  Backs up the share definitions and removes shares that are not built-in administrative shares
  and not in the allow list. Shares with open files are skipped unless explicitly allowed.
  Exits 0 after verification, 1 if a share is left.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowedShareNames   = @()
$RemoveShares        = $false
$RemoveWithOpenFiles = $false
$BackupRoot          = Join-Path $env:ProgramData 'IntuneRemediations\Backup\NonDefaultSmbShares'
$ShareRegistryKey    = 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Shares'

$PackageName = 'NonDefaultSmbShares'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-CustomShare {
    $defaultNames = @('ADMIN$', 'IPC$', 'print$', 'FAX$', 'SYSVOL', 'NETLOGON')
    foreach ($share in @(Get-SmbShare -Special $false -ErrorAction Stop)) {
        if ($defaultNames -contains $share.Name) { continue }
        if ($share.Name -match '^[A-Za-z]\$$') { continue }
        if ($AllowedShareNames -contains $share.Name) { continue }
        if (-not $share.Path) { continue }
        [pscustomobject]@{ Name = $share.Name; Path = $share.Path; Description = $share.Description }
    }
}

function Test-ShareInUse { param([string]$Path)
    $prefix = $Path.TrimEnd('\')
    foreach ($file in @(Get-SmbOpenFile -ErrorAction SilentlyContinue)) {
        if (-not $file.Path) { continue }
        if ($file.Path.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($file.Path.StartsWith("$prefix\", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Save-ShareBackup { param($Share)
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    $acl = @()
    try { $acl = @(Get-SmbShareAccess -Name $Share.Name -ErrorAction Stop | Select-Object AccountName, AccessControlType, AccessRight) } catch { }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeName = $Share.Name -replace '[^A-Za-z0-9._-]', '_'
    $data = [pscustomobject]@{
        CapturedAt  = (Get-Date).ToString('s')
        Name        = $Share.Name
        Path        = $Share.Path
        Description = $Share.Description
        Acl         = $acl
    }
    $data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $BackupRoot "$stamp-$safeName.json") -Encoding UTF8
}

function Save-RegistryBackup {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    $target = Join-Path $BackupRoot ("LanmanServerShares-{0}.reg" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    & reg.exe export $ShareRegistryKey $target /y | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-IRTLog "reg export failed with code $LASTEXITCODE" 'WARN' }
}

try {
    if (-not (Get-Command -Name Get-SmbShare -ErrorAction SilentlyContinue)) { Exit-Script 0 'NotApplicable | SmbShare module not available' }

    $shares = @(Get-CustomShare)
    if ($shares.Count -eq 0) { Exit-Script 0 'Healthy | CustomShares=0' }

    if (-not $RemoveShares) {
        $list = (@($shares | ForEach-Object { $_.Name }) -join ',')
        Exit-Script 1 "ReportOnly | CustomShares=$($shares.Count); Names=$list"
    }

    Save-RegistryBackup
    $removed = @()
    $blocked = @()
    $failed  = @()
    foreach ($share in $shares) {
        if ((Test-ShareInUse -Path $share.Path) -and (-not $RemoveWithOpenFiles)) {
            $blocked += $share.Name
            Write-IRTLog "Share $($share.Name) has open files, skipped"
            continue
        }
        try {
            Save-ShareBackup -Share $share
            Remove-SmbShare -Name $share.Name -Force -ErrorAction Stop
            $removed += $share.Name
            Write-IRTLog "Removed share $($share.Name) pointing to $($share.Path)"
        }
        catch {
            $failed += $share.Name
            Write-IRTLog "Remove $($share.Name): $($_.Exception.Message)" 'ERROR'
        }
    }

    $left = @(Get-CustomShare)
    if ($left.Count -eq 0) { Exit-Script 0 "Fixed | Removed=$($removed.Count); Names=$($removed -join ','); Backup=$BackupRoot" }

    $leftNames = (@($left | ForEach-Object { $_.Name }) -join ',')
    $summary = "Failed | Left=$($left.Count); Names=$leftNames; Removed=$($removed.Count)"
    if ($blocked.Count -gt 0) { $summary = "$summary; InUse=$($blocked -join ',')" }
    if ($failed.Count -gt 0) { $summary = "$summary; Errors=$($failed -join ',')" }
    Exit-Script 1 $summary
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
