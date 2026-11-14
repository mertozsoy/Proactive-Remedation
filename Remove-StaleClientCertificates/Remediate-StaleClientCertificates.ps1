<#
.SYNOPSIS
  Remediation script for approved obsolete device client certificates.

.DESCRIPTION
  Backs up approved obsolete certificates and removes them without deleting private keys.
  Requires a retained replacement. Unexpired removal is disabled by default.
  Exits 0 after verification, 1 for errors or blocked removal.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$KeepThumbprint = ''
$ObsoleteThumbprints = @()
$MinimumRemainingDays = 14
$RemoveUnexpiredDuplicates = $false
$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup\StaleClientCertificates'

$PackageName = 'StaleClientCertificates'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
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
function Get-ApprovedCertificateState {
    if ($KeepThumbprint -notmatch '^[A-Fa-f0-9]{40}$' -or $ObsoleteThumbprints.Count -eq 0 -or $MinimumRemainingDays -lt 1) {
        throw 'ConfigurationRequired'
    }
    foreach ($thumbprint in $ObsoleteThumbprints) {
        if ($thumbprint -notmatch '^[A-Fa-f0-9]{40}$' -or $thumbprint -eq $KeepThumbprint) { throw 'InvalidRemovalList' }
    }
    $certificates = @(Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction Stop)
    $keep = @($certificates | Where-Object { $_.Thumbprint -eq $KeepThumbprint })
    $now = Get-Date
    if ($keep.Count -ne 1) { throw 'ReplacementMissing' }
    $replacement = $keep[0]
    if (-not $replacement.HasPrivateKey -or $replacement.NotBefore -gt $now -or $replacement.NotAfter -le $now.AddDays($MinimumRemainingDays)) {
        throw 'ReplacementNotUsable'
    }
    $replacementEku = $replacement.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' }
    if (@($replacementEku.EnhancedKeyUsages | Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.2' }).Count -eq 0) {
        throw 'ReplacementMissingClientAuthentication'
    }
    $obsolete = @($certificates | Where-Object { $ObsoleteThumbprints -contains $_.Thumbprint })
    foreach ($certificate in $obsolete) {
        $certificateEku = $certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' }
        if (@($certificateEku.EnhancedKeyUsages | Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.2' }).Count -eq 0) {
            throw 'RemovalTargetMissingClientAuthentication'
        }
        if ([Convert]::ToBase64String($certificate.SubjectName.RawData) -ne [Convert]::ToBase64String($replacement.SubjectName.RawData) -or
            [Convert]::ToBase64String($certificate.IssuerName.RawData) -ne [Convert]::ToBase64String($replacement.IssuerName.RawData)) {
            throw 'CertificateIdentityMismatch'
        }
    }
    [pscustomobject]@{
        Replacement = $replacement
        Obsolete = $obsolete
        Expired = @($obsolete | Where-Object { $_.NotAfter -le $now }).Count
        Unexpired = @($obsolete | Where-Object { $_.NotAfter -gt $now }).Count
    }
}

try {
    $ErrorActionPreference = 'Stop'
    $removed = 0
    $stage = 'Validation'
    $state = Get-ApprovedCertificateState
    if ($state.Obsolete.Count -eq 0) { Exit-Script 0 'Healthy | Obsolete=0; Replacement=Present' }
    $targets = @($state.Obsolete | Where-Object { $_.NotAfter -le (Get-Date) -or $RemoveUnexpiredDuplicates })
    if ($targets.Count -gt 0) {
        $stage = 'Backup'
        $backupDirectory = Join-Path $BackupRoot ([guid]::NewGuid().ToString('N'))
        New-Item -Path $backupDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        foreach ($certificate in $targets) {
            $backupFile = Join-Path $backupDirectory ($certificate.Thumbprint + '.cer')
            Export-Certificate -Cert $certificate -FilePath $backupFile -Type CERT -NoClobber -ErrorAction Stop | Out-Null
            $backup = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $backupFile
            try {
                if ($backup.Thumbprint -ne $certificate.Thumbprint) { throw 'BackupVerificationFailed' }
            }
            finally { $backup.Dispose() }
        }
        $stage = 'Removal'
        foreach ($certificate in $targets) {
            $current = Get-ApprovedCertificateState
            $stillPresent = @($current.Obsolete | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint })
            if ($stillPresent.Count -eq 0) { continue }
            if (-not $RemoveUnexpiredDuplicates -and $stillPresent[0].NotAfter -gt (Get-Date)) { throw 'TargetNoLongerExpired' }
            $certificatePath = 'Cert:\LocalMachine\My\' + $certificate.Thumbprint
            Remove-Item -Path $certificatePath -Confirm:$false -ErrorAction Stop
            if (Test-Path -Path $certificatePath -ErrorAction Stop) { throw 'RemovalVerificationFailed' }
            $removed++
        }
    }
    $stage = 'Verification'
    $remaining = Get-ApprovedCertificateState
    if ($remaining.Obsolete.Count -gt 0) {
        Exit-Script 1 "Blocked | Removed=$removed; Remaining=$($remaining.Obsolete.Count); Action=ApproveUnexpiredRemoval"
    }
    Exit-Script 0 "Fixed | Removed=$removed; Remaining=0; Replacement=Present; PrivateKeys=Retained"
}
catch { Exit-Script 1 "Failed | Stage=$stage; Removed=$removed; Action=ReviewCertificatesAndBackup" }
