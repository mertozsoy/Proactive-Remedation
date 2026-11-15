<#
.SYNOPSIS
  Remediation script for approved expired certificates in personal stores.

.DESCRIPTION
  When enabled, exports and removes approved expired certificates without deleting private keys.
  Exits 0 only when no non-excluded expired certificates remain, otherwise 1.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$RemoveExpiredCertificates = $false
$StoreLocations = @('CurrentUser', 'LocalMachine')
$ExcludedThumbprints = @()
$ApprovedUserThumbprints = @()
$ApprovedMachineThumbprints = @()

$PackageName = 'ExpiredPersonalCertificates'
$Phase = 'Remediate'
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
    $removed = 0
    $stage = 'Validation'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal -ArgumentList $identity
    $isAdministrator = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    $logRoot = if ($identity.IsSystem) { Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs' } else { Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs' }
    $backupRoot = if ($identity.IsSystem) { Join-Path $env:ProgramData 'IntuneRemediations\Backup\ExpiredPersonalCertificates' } else { Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup\ExpiredPersonalCertificates' }
    $LogFile = Join-Path $logRoot "IRT_$PackageName.log"
    New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
    if ($StoreLocations.Count -eq 0) { throw 'NoStoresSelected' }
    foreach ($location in $StoreLocations) {
        if ($location -notin @('CurrentUser', 'LocalMachine')) { throw 'InvalidStoreLocation' }
    }
    foreach ($thumbprint in @($ExcludedThumbprints) + @($ApprovedUserThumbprints) + @($ApprovedMachineThumbprints)) {
        if ($thumbprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'InvalidThumbprint' }
    }
    if ($identity.IsSystem -and $StoreLocations -contains 'CurrentUser') { throw 'SystemCannotTargetSignedInUserStore' }
    $stage = 'Inspection'
    $expired = @(Get-ExpiredPersonalCertificate)
    if ($expired.Count -eq 0) { Exit-Script 0 'Healthy | Remaining=0; Removed=0' }
    if (-not $RemoveExpiredCertificates) { Exit-Script 1 "Blocked | Removed=0; Remaining=$($expired.Count); Reason=RemovalDisabled" }
    $unapproved = 0
    $requiresElevation = 0
    $backupDirectory = Join-Path $backupRoot ([guid]::NewGuid().ToString('N'))
    foreach ($entry in $expired) {
        $approved = if ($entry.Location -eq 'CurrentUser') { $ApprovedUserThumbprints } else { $ApprovedMachineThumbprints }
        if ($approved -notcontains $entry.Certificate.Thumbprint) { $unapproved++; continue }
        if ($entry.Location -eq 'LocalMachine' -and -not $isAdministrator) { $requiresElevation++; continue }
        $stage = 'Backup'
        $certificatePath = 'Cert:\{0}\My\{1}' -f $entry.Location, $entry.Certificate.Thumbprint
        if (-not (Test-Path -Path $certificatePath -ErrorAction Stop)) { continue }
        $current = Get-Item -Path $certificatePath -ErrorAction Stop
        if ($current.NotAfter.ToUniversalTime() -ge (Get-Date).ToUniversalTime()) { continue }
        New-Item -Path $backupDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $backupFile = Join-Path $backupDirectory ('{0}_{1}.cer' -f $entry.Location, $current.Thumbprint)
        Export-Certificate -Cert $current -FilePath $backupFile -Type CERT -NoClobber -ErrorAction Stop | Out-Null
        $backup = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $backupFile
        try {
            if ([Convert]::ToBase64String($backup.RawData) -ne [Convert]::ToBase64String($current.RawData)) { throw 'BackupMismatch' }
        }
        finally { $backup.Dispose() }
        $stage = 'Removal'
        $current = Get-Item -Path $certificatePath -ErrorAction Stop
        if ($current.NotAfter.ToUniversalTime() -ge (Get-Date).ToUniversalTime()) { continue }
        Remove-Item -Path $certificatePath -Confirm:$false -ErrorAction Stop
        if (Test-Path -Path $certificatePath -ErrorAction Stop) { throw 'RemovalVerificationFailed' }
        $removed++
    }
    $stage = 'Verification'
    $remaining = @(Get-ExpiredPersonalCertificate)
    if ($remaining.Count -gt 0) {
        Exit-Script 1 "Blocked | Removed=$removed; Remaining=$($remaining.Count); Unapproved=$unapproved; RequiresElevation=$requiresElevation"
    }
    Exit-Script 0 "Fixed | Removed=$removed; Remaining=0; PrivateKeys=Retained"
}
catch { Exit-Script 1 "Error: RemediationFailed | Stage=$stage; Removed=$removed; Action=ReviewConfigurationPermissionsAndBackup" }
