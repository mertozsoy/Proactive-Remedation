<#
.SYNOPSIS
  Remediation script for explicitly blocklisted machine root certificates.

.DESCRIPTION
  When enabled, backs up and removes only blocklisted roots approved as unmanaged.
  Protects Group Policy roots, nonlocal roots, and certificates with private keys.
  Exits 0 only when no blocklisted root remains, otherwise exits 1.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BlocklistedThumbprints = @()
$ApprovedUnmanagedThumbprints = @()
$EnableRemediation = $false
$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup\BlocklistedRootCAs'

$PackageName = 'BlocklistedRootCAs'
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
function ConvertTo-ThumbprintList { param([object[]]$Values)
    foreach ($value in $Values) {
        $thumbprint = ([string]$value -replace '\s', '').ToUpperInvariant()
        if ($thumbprint -notmatch '^[0-9A-F]{40}$') { throw 'Invalid SHA1 thumbprint configuration.' }
        $thumbprint
    }
}
function Get-BlockedRoot { param([string[]]$Blocked, [string[]]$Approved)
    foreach ($certificate in Get-ChildItem -Path 'Cert:\LocalMachine\Root' -ErrorAction Stop) {
        $thumbprint = $certificate.Thumbprint.ToUpperInvariant()
        if ($Blocked -notcontains $thumbprint) { continue }
        $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\Certificates\$thumbprint"
        $localPath = "HKLM:\SOFTWARE\Microsoft\SystemCertificates\Root\Certificates\$thumbprint"
        $reason = 'Eligible'
        if (Test-Path -LiteralPath $policyPath -ErrorAction Stop) { $reason = 'GroupPolicy' }
        elseif ($Approved -notcontains $thumbprint) { $reason = 'OwnershipNotApproved' }
        elseif (-not (Test-Path -LiteralPath $localPath -ErrorAction Stop)) { $reason = 'NonLocalStore' }
        elseif ($certificate.HasPrivateKey) { $reason = 'PrivateKeyPresent' }
        [pscustomobject]@{ Thumbprint = $thumbprint; Reason = $reason }
    }
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Requires64BitPowerShell' }
    $blocked = @(ConvertTo-ThumbprintList -Values $BlocklistedThumbprints | Sort-Object -Unique)
    $approved = @(ConvertTo-ThumbprintList -Values $ApprovedUnmanagedThumbprints | Sort-Object -Unique)
    if ($blocked.Count -eq 0) { Exit-Script 0 'NotApplicable | Reason=BlocklistNotConfigured' }
    $found = @(Get-BlockedRoot -Blocked $blocked -Approved $approved)
    if ($found.Count -eq 0) { Exit-Script 0 'Healthy | BlocklistedRoots=0' }
    foreach ($item in $found) { Write-IRTLog "Thumbprint=$($item.Thumbprint); Reason=$($item.Reason)" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | BlocklistedRoots=$($found.Count); Reason=RemediationDisabled" }
    $eligible = @($found | Where-Object { $_.Reason -eq 'Eligible' })
    $removed = 0
    $errors = 0
    if ($eligible.Count -gt 0) {
        $backupDirectory = Join-Path $BackupRoot ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $backupDirectory -ItemType Directory -ErrorAction Stop
        $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
        foreach ($item in $eligible) {
            try {
                $thumbprint = $item.Thumbprint
                $current = @(Get-BlockedRoot -Blocked @($thumbprint) -Approved $approved)
                if ($current.Count -eq 0) { continue }
                if ($current[0].Reason -ne 'Eligible') { continue }
                $certificatePath = "Cert:\LocalMachine\Root\$thumbprint"
                $certificate = Get-Item -Path $certificatePath -ErrorAction Stop
                $cerFile = Join-Path $backupDirectory "$thumbprint.cer"
                $regFile = Join-Path $backupDirectory "$thumbprint.reg"
                $null = Export-Certificate -Cert $certificate -FilePath $cerFile -Type CERT -NoClobber -ErrorAction Stop
                $backupCertificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $cerFile
                try {
                    if ($backupCertificate.Thumbprint -ne $thumbprint) { throw 'Certificate backup mismatch.' }
                }
                finally { $backupCertificate.Dispose() }
                $registryPath = "HKLM\SOFTWARE\Microsoft\SystemCertificates\Root\Certificates\$thumbprint"
                $null = & $regExe export $registryPath $regFile /y 2>&1
                if ($LASTEXITCODE -ne 0) { throw 'Registry backup failed.' }
                if ((Get-Item -LiteralPath $regFile -ErrorAction Stop).Length -eq 0) { throw 'Empty registry backup.' }
                $current = @(Get-BlockedRoot -Blocked @($thumbprint) -Approved $approved)
                if ($current.Count -eq 0) { continue }
                if ($current[0].Reason -ne 'Eligible') { continue }
                Remove-Item -Path $certificatePath -Confirm:$false -ErrorAction Stop
                if (Test-Path -Path $certificatePath -ErrorAction Stop) { throw 'Certificate remains.' }
                $removed++
                Write-IRTLog "Removed=$thumbprint"
            }
            catch {
                $errors++
                Write-IRTLog "Thumbprint=$($item.Thumbprint); RemovalFailed=True; HResult=$($_.Exception.HResult)" 'ERROR'
            }
        }
    }
    $remaining = @(Get-BlockedRoot -Blocked $blocked -Approved $approved)
    $protected = @($remaining | Where-Object { $_.Reason -ne 'Eligible' }).Count
    if ($remaining.Count -gt 0 -or $errors -gt 0) {
        Exit-Script 1 "Failed | Removed=$removed; Remaining=$($remaining.Count); Protected=$protected; Errors=$errors"
    }
    Exit-Script 0 "Fixed | Removed=$removed; Remaining=0; Protected=0; Errors=0"
}
catch { Exit-Script 1 "Failed | Reason=RemediationError; HResult=$($_.Exception.HResult)" }
