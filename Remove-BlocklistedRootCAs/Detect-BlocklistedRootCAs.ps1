<#
.SYNOPSIS
  Detection script for explicitly blocklisted machine root certificates.

.DESCRIPTION
  Checks LocalMachine Root against an administrator supplied SHA1 thumbprint list.
  Exits 1 for matching roots or errors, 0 for no matches or no configured list.
  Does not infer trust from certificate names, expiration, or chain validation.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$BlocklistedThumbprints = @()
$ApprovedUnmanagedThumbprints = @()

$PackageName = 'BlocklistedRootCAs'
$Phase = 'Detect'
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
    foreach ($item in $found) { Write-IRTLog "Thumbprint=$($item.Thumbprint); Reason=$($item.Reason)" }
    if ($found.Count -eq 0) { Exit-Script 0 'Healthy | BlocklistedRoots=0' }
    $protected = @($found | Where-Object { $_.Reason -ne 'Eligible' }).Count
    Exit-Script 1 "Drift | BlocklistedRoots=$($found.Count); Protected=$protected"
}
catch { Exit-Script 1 "Failed | Reason=InspectionError; HResult=$($_.Exception.HResult)" }
