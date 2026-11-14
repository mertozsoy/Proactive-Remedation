<#
.SYNOPSIS
  Detection script for expiring machine certificates.

.DESCRIPTION
  Lists machine certificates, including the Intune MDM certificate, that expire within the threshold. Report only.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$WarnDays = 30

$IgnoreIssuerRegex = 'CN=localhost|MS-Organization-P2P-Access'

$PackageName = 'CertificateExpiry'
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
    $now      = Get-Date
    $limit    = $now.AddDays($WarnDays)
    $findings = New-Object System.Collections.Generic.List[string]
    $certs    = Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop

    $mdm = $certs | Where-Object { $_.Issuer -like '*Microsoft Intune MDM Device CA*' } | Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $mdm)                   { $findings.Add('IntuneMDMCert=Missing') }
    elseif ($mdm.NotAfter -lt $now)  { $findings.Add("IntuneMDMCert=Expired($($mdm.NotAfter.ToString('yyyy-MM-dd')))") }
    elseif ($mdm.NotAfter -lt $limit){ $findings.Add("IntuneMDMCert=Expiring($($mdm.NotAfter.ToString('yyyy-MM-dd')))") }

    $certs | Where-Object {
        $_.HasPrivateKey -and $_.NotAfter -lt $limit -and $_.NotAfter -gt $now.AddDays(-90) -and
        $_.Issuer -notlike '*Microsoft Intune MDM Device CA*' -and $_.Issuer -notmatch $IgnoreIssuerRegex
    } | Sort-Object NotAfter | ForEach-Object {
        $cn = ($_.Subject -split ',')[0]
        $findings.Add(('{0} exp {1:yyyy-MM-dd} ({2})' -f $cn, $_.NotAfter, ($_.Issuer -split ',')[0]))
    }

    $mdmExp = if ($mdm) { $mdm.NotAfter.ToString('yyyy-MM-dd') } else { 'n/a' }
    if ($findings.Count) { Exit-Script 1 "Findings=$($findings.Count) | $($findings -join ' ; ')" }
    Exit-Script 0 "OK | IntuneMDMCert expires $mdmExp; nothing else within $WarnDays days"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
