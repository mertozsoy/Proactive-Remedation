<#
.SYNOPSIS
  Detection script for expired certificates in personal stores.

.DESCRIPTION
  Reads selected personal stores and counts expired certificates outside the exclusion list.
  Exits 1 for expired certificates or errors and 0 when none remain.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$StoreLocations = @('CurrentUser', 'LocalMachine')
$ExcludedThumbprints = @()

$PackageName = 'ExpiredPersonalCertificates'
$Phase = 'Detect'
$LogFile = $null
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}
function Get-ExpiredPersonalCertificate {
    $cutoff = (Get-Date).ToUniversalTime()
    foreach ($location in $StoreLocations) {
        foreach ($certificate in @(Get-ChildItem -Path "Cert:\$location\My" -ErrorAction Stop)) {
            if ($certificate.NotAfter.ToUniversalTime() -ge $cutoff) { continue }
            if ($ExcludedThumbprints -contains $certificate.Thumbprint) { continue }
            [pscustomobject]@{ Location = $location; Certificate = $certificate }
        }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $logRoot = if ($identity.IsSystem) { Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs' } else { Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs' }
    $LogFile = Join-Path $logRoot "IRT_$PackageName.log"
    New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
    if ($StoreLocations.Count -eq 0) { throw 'NoStoresSelected' }
    foreach ($location in $StoreLocations) {
        if ($location -notin @('CurrentUser', 'LocalMachine')) { throw 'InvalidStoreLocation' }
    }
    foreach ($thumbprint in $ExcludedThumbprints) {
        if ($thumbprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'InvalidExclusion' }
    }
    if ($identity.IsSystem -and $StoreLocations -contains 'CurrentUser') { throw 'SystemCannotTargetSignedInUserStore' }
    $expired = @(Get-ExpiredPersonalCertificate)
    $userCount = @($expired | Where-Object { $_.Location -eq 'CurrentUser' }).Count
    $machineCount = @($expired | Where-Object { $_.Location -eq 'LocalMachine' }).Count
    $summary = "CurrentUser=$userCount; LocalMachine=$machineCount; ExcludedRules=$($ExcludedThumbprints.Count)"
    if ($expired.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 'Error: InspectionFailed | Action=ReviewScopePermissionsAndConfiguration' }
