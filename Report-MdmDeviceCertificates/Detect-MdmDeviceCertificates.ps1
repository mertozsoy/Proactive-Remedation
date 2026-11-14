<#
.SYNOPSIS
  Detection script for duplicate or expired Intune MDM device certificates.

.DESCRIPTION
  Lists the certificates issued by the Intune MDM device CAs in the local machine store. Exits 1 if there is more than one valid certificate, an expired leftover or no valid certificate. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$Issuers = [ordered]@{
    'IntuneMDM'  = 'Microsoft Intune MDM Device CA'
    'DeviceMgmt' = 'Microsoft Device Management Device CA'
}
$MaxValidPerIssuer = 1

$PackageName = 'MdmDeviceCertificates'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

try {
    $now    = Get-Date
    $store  = @(Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction Stop)
    $issues = New-Object System.Collections.Generic.List[string]
    $parts  = New-Object System.Collections.Generic.List[string]
    $total  = 0

    foreach ($label in $Issuers.Keys) {
        $issuerName = $Issuers[$label]
        $certs = @($store | Where-Object { $_.Issuer -like "*CN=$issuerName*" })
        if ($certs.Count -eq 0) { continue }
        $total  += $certs.Count
        $valid   = @($certs | Where-Object { $_.NotBefore -le $now -and $_.NotAfter -gt $now } | Sort-Object NotAfter -Descending)
        $expired = @($certs | Where-Object { $_.NotAfter -le $now })

        if ($valid.Count -gt $MaxValidPerIssuer) { $issues.Add("Duplicate:$label=$($valid.Count)") }
        if ($expired.Count -gt 0)                { $issues.Add("Expired:$label=$($expired.Count)") }
        if ($valid.Count -eq 0)                  { $issues.Add("NoValid:$label") }

        $newest = if ($valid.Count -gt 0) { '{0:yyyy-MM-dd}' -f $valid[0].NotAfter } else { 'None' }
        $parts.Add(('{0}Valid={1}; {0}Expired={2}; {0}NewestExpires={3}' -f $label, $valid.Count, $expired.Count, $newest))
        foreach ($cert in $certs) {
            Write-IRTLog ('{0} Thumbprint={1} NotBefore={2:yyyy-MM-dd} NotAfter={3:yyyy-MM-dd} HasPrivateKey={4}' -f $label, $cert.Thumbprint, $cert.NotBefore, $cert.NotAfter, $cert.HasPrivateKey)
        }
    }

    if ($total -eq 0) { Exit-Script 0 'NotApplicable | MdmCertificates=0' }
    $summary = $parts -join '; '
    if ($issues.Count -gt 0) { Exit-Script 1 "Attention ($($issues -join ',')) | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
