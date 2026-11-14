<#
.SYNOPSIS
  Detection script for a missing or stale MDM SSL client certificate reference.

.DESCRIPTION
  Compares the SslClientCertReference of the Intune OMA-DM account with the MDM certificate on the device. Exits 1 if the reference is missing, points to an unusable certificate or differs from the current MDM certificate. Exits 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ProviderId         = 'MS DM Server'
$EnrollmentsRoot    = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$OmadmAccountsRoot  = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
$CertificateStore   = 'Cert:\LocalMachine\My'
$IntuneIssuerMatch  = '*Intune MDM*'
$ReferenceValueName = 'SslClientCertReference'
$CriteriaValueName  = 'SslClientCertSearchCriteria'
$MinimumRemainingDays = 1

$PackageName = 'MDMCertReference'
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

function Get-IntuneEnrollment {
    $found = @()
    foreach ($key in Get-ChildItem -LiteralPath $EnrollmentsRoot -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($props.ProviderID -ne $ProviderId) { continue }
        $state = 0
        if ($null -ne $props.EnrollmentState) { $state = [int]$props.EnrollmentState }
        $found += [pscustomobject]@{
            Id             = $key.PSChildName
            State          = $state
            CertThumbprint = [string]$props.DMPCertThumbPrint
        }
    }
    if ($found.Count -eq 0) { return $null }
    $active = @($found | Where-Object { $_.State -eq 1 })
    if ($active.Count -gt 0) { return $active[0] }
    return $found[0]
}

function Get-MdmCertificate {
    param([string]$Thumbprint)
    $clean = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if (-not $clean) { return $null }
    Get-ChildItem -Path $CertificateStore -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $clean } |
        Select-Object -First 1
}

function Test-MdmCertificateUsable {
    param($Certificate)
    if ($null -eq $Certificate) { return $false }
    if (-not $Certificate.HasPrivateKey) { return $false }
    if ($Certificate.NotAfter -le (Get-Date).AddDays($MinimumRemainingDays)) { return $false }
    return $true
}

function Select-ExpectedCertificate {
    param($Enrollment)
    $fromEnrollment = Get-MdmCertificate -Thumbprint $Enrollment.CertThumbprint
    if (Test-MdmCertificateUsable -Certificate $fromEnrollment) { return $fromEnrollment }
    $candidates = @(Get-ChildItem -Path $CertificateStore -ErrorAction SilentlyContinue | Where-Object {
        $_.Issuer -like $IntuneIssuerMatch -and
        $_.HasPrivateKey -and
        $_.NotAfter -gt (Get-Date).AddDays($MinimumRemainingDays)
    } | Sort-Object NotAfter -Descending)
    if ($candidates.Count -gt 0) { return $candidates[0] }
    return $null
}

try {
    $enrollment = Get-IntuneEnrollment
    if ($null -eq $enrollment) { Exit-Script 0 'NotApplicable | IntuneEnrollment=Missing' }

    $accountPath = Join-Path $OmadmAccountsRoot $enrollment.Id
    if (-not (Test-Path -LiteralPath $accountPath)) {
        Exit-Script 1 "Drift | Enrollment=$($enrollment.Id); OmadmAccount=Missing; CertUsable=True; Action=Reenroll"
    }

    $reference = $null
    $referenceProps = Get-ItemProperty -LiteralPath $accountPath -Name $ReferenceValueName -ErrorAction SilentlyContinue
    if ($null -ne $referenceProps) { $reference = [string]$referenceProps.$ReferenceValueName }
    $referenceState = 'Missing'
    $referenceThumb = ''
    if ($reference) {
        $referenceState = 'Present'
        $referenceThumb = ($reference -split ';')[-1].Trim()
    }

    $criteria = $null
    $criteriaProps = Get-ItemProperty -LiteralPath (Join-Path $accountPath 'Protected') -Name $CriteriaValueName -ErrorAction SilentlyContinue
    if ($null -ne $criteriaProps) { $criteria = [string]$criteriaProps.$CriteriaValueName }
    $criteriaState = 'Missing'
    if ($criteria) { $criteriaState = 'Present' }

    $expected = Select-ExpectedCertificate -Enrollment $enrollment
    if ($null -eq $expected) {
        Exit-Script 1 "Drift | Enrollment=$($enrollment.Id); Reference=$referenceState; ExpectedThumb=None; CertUsable=False; SearchCriteria=$criteriaState; Action=Reenroll"
    }
    $expectedThumb = $expected.Thumbprint

    $summary = 'Enrollment={0}; Reference={1}; ExpectedThumb={2}; SearchCriteria={3}' -f $enrollment.Id, $referenceState, $expectedThumb, $criteriaState

    if (-not $reference) { Exit-Script 1 "Drift | $summary; CertUsable=True; Action=WriteReference" }

    $referenceCert = Get-MdmCertificate -Thumbprint $referenceThumb
    if (-not (Test-MdmCertificateUsable -Certificate $referenceCert)) {
        Exit-Script 1 "Drift | $summary; CertUsable=True; Action=WriteReference"
    }
    if ($referenceThumb.ToUpperInvariant() -ne $expectedThumb) {
        Exit-Script 1 "Drift | $summary; CertUsable=True; Action=WriteReference"
    }

    Exit-Script 0 "Healthy | $summary; CertUsable=True"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
