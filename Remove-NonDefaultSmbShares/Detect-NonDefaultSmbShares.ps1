<#
.SYNOPSIS
  Detection script for non-default SMB shares on workstations.

.DESCRIPTION
  Lists SMB shares that are not built-in administrative shares and not in the allow list.
  Flags shares that grant Everyone or Authenticated Users access.
  Exits 1 if a share is found, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AllowedShareNames = @()
$FlagWeakAccess    = $true
$WeakAccessSids    = @('S-1-1-0', 'S-1-5-11')
$MaxListedNames    = 12

$PackageName = 'NonDefaultSmbShares'
$Phase       = 'Detect'
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

function ConvertTo-Sid { param([string]$Name)
    try { return (New-Object System.Security.Principal.NTAccount($Name)).Translate([System.Security.Principal.SecurityIdentifier]).Value }
    catch { return '' }
}

function Test-WeakShareAcl { param([string]$Name)
    if (-not $FlagWeakAccess) { return $false }
    foreach ($entry in @(Get-SmbShareAccess -Name $Name -ErrorAction Stop)) {
        if ($entry.AccessControlType -ne 'Allow') { continue }
        if ($WeakAccessSids -contains (ConvertTo-Sid -Name $entry.AccountName)) { return $true }
    }
    return $false
}

function Get-CustomShare {
    $defaultNames = @('ADMIN$', 'IPC$', 'print$', 'FAX$', 'SYSVOL', 'NETLOGON')
    foreach ($share in @(Get-SmbShare -Special $false -ErrorAction Stop)) {
        if ($defaultNames -contains $share.Name) { continue }
        if ($share.Name -match '^[A-Za-z]\$$') { continue }
        if ($AllowedShareNames -contains $share.Name) { continue }
        if (-not $share.Path) { continue }
        [pscustomobject]@{
            Name    = $share.Name
            Path    = $share.Path
            WeakAcl = (Test-WeakShareAcl -Name $share.Name)
        }
    }
}

try {
    if (-not (Get-Command -Name Get-SmbShare -ErrorAction SilentlyContinue)) { Exit-Script 0 'NotApplicable | SmbShare module not available' }

    $shares = @(Get-CustomShare)
    if ($shares.Count -eq 0) { Exit-Script 0 'Healthy | CustomShares=0' }

    $names = (@($shares | Select-Object -First $MaxListedNames | ForEach-Object { $_.Name }) -join ',')
    $summary = "CustomShares=$($shares.Count); Names=$names"
    $weak = @($shares | Where-Object { $_.WeakAcl } | Select-Object -First $MaxListedNames | ForEach-Object { $_.Name })
    if ($weak.Count -gt 0) { $summary = "$summary; WeakAcl=$($weak -join ',')" }
    Exit-Script 1 "Drift | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
