<#
.SYNOPSIS
  Remediation script for a missing or stale MDM SSL client certificate reference.

.DESCRIPTION
  Writes the SslClientCertReference of the Intune OMA-DM account from the current MDM certificate, then starts an MDM sync session. Report only by default. Exits 0 when the reference is correct and 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $false
$TriggerSync       = $true

$ProviderId         = 'MS DM Server'
$EnrollmentsRoot    = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$OmadmAccountsRoot  = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
$CertificateStore   = 'Cert:\LocalMachine\My'
$IntuneIssuerMatch  = '*Intune MDM*'
$ReferenceValueName = 'SslClientCertReference'
$CriteriaValueName  = 'SslClientCertSearchCriteria'
$MinimumRemainingDays = 1
$BackupFolder       = Join-Path $env:ProgramData 'IntuneRemediations\Backup\MDMCertReference'

$PackageName = 'MDMCertReference'
$Phase       = 'Remediate'
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

function Get-ReferenceThumbprint {
    param([string]$AccountPath)
    $props = Get-ItemProperty -LiteralPath $AccountPath -Name $ReferenceValueName -ErrorAction SilentlyContinue
    if ($null -eq $props) { return '' }
    $value = [string]$props.$ReferenceValueName
    if (-not $value) { return '' }
    return ($value -split ';')[-1].Trim()
}

function Invoke-MdmSync {
    param([string]$EnrollmentId)
    $taskPath = "\Microsoft\Windows\EnterpriseMgmt\$EnrollmentId\"
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName 'PushLaunch' -ErrorAction SilentlyContinue
    if ($null -eq $task) { return 'NoTask' }
    if ($task.State -eq 'Disabled') { Enable-ScheduledTask -InputObject $task | Out-Null }
    Start-ScheduledTask -InputObject $task -ErrorAction Stop
    return 'Started'
}

try {
    $enrollment = Get-IntuneEnrollment
    if ($null -eq $enrollment) { Exit-Script 0 'NotApplicable | IntuneEnrollment=Missing' }

    $accountPath = Join-Path $OmadmAccountsRoot $enrollment.Id
    if (-not (Test-Path -LiteralPath $accountPath)) {
        Exit-Script 1 "Failed | Enrollment=$($enrollment.Id); OmadmAccount=Missing; Action=Reenroll"
    }

    $expected = Select-ExpectedCertificate -Enrollment $enrollment
    if ($null -eq $expected) {
        Exit-Script 1 "Failed | Enrollment=$($enrollment.Id); CertUsable=False; Action=Reenroll"
    }
    $expectedThumb = $expected.Thumbprint

    $currentThumb = Get-ReferenceThumbprint -AccountPath $accountPath
    $currentCert = Get-MdmCertificate -Thumbprint $currentThumb
    if ($currentThumb -eq $expectedThumb -and (Test-MdmCertificateUsable -Certificate $currentCert)) {
        Exit-Script 0 "Healthy | Enrollment=$($enrollment.Id); Reference=Present; Thumbprint=$expectedThumb"
    }

    $criteriaProps = Get-ItemProperty -LiteralPath (Join-Path $accountPath 'Protected') -Name $CriteriaValueName -ErrorAction SilentlyContinue
    $criteriaState = 'Missing'
    if ($null -ne $criteriaProps) { $criteriaState = 'Present' }

    $referenceState = 'Missing'
    if ($currentThumb) { $referenceState = 'Present' }

    if (-not $EnableRemediation) {
        Exit-Script 1 "ReportOnly | Enrollment=$($enrollment.Id); Reference=$referenceState; ExpectedThumb=$expectedThumb; SearchCriteria=$criteriaState; EnableRemediation=False"
    }

    if (-not (Test-Path -LiteralPath $BackupFolder)) { New-Item -Path $BackupFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    $backupFile = Join-Path $BackupFolder ('OMADM_Accounts_{0}_{1}.reg' -f $enrollment.Id, (Get-Date -Format 'yyyyMMddHHmmss'))
    & reg.exe export "HKLM\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$($enrollment.Id)" $backupFile /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupFile)) {
        Exit-Script 1 "Failed | Enrollment=$($enrollment.Id); Backup=Failed; Changed=False"
    }
    Write-IRTLog "Backup written to $backupFile"

    $newValue = 'MY;System;{0}' -f $expectedThumb
    New-ItemProperty -LiteralPath $accountPath -Name $ReferenceValueName -Value $newValue -PropertyType String -Force -ErrorAction Stop | Out-Null

    $verifiedThumb = Get-ReferenceThumbprint -AccountPath $accountPath
    if ($verifiedThumb -ne $expectedThumb) {
        Exit-Script 1 "Failed | Enrollment=$($enrollment.Id); Reference=NotVerified; Backup=$backupFile"
    }

    $syncState = 'Skipped'
    if ($TriggerSync) {
        try { $syncState = Invoke-MdmSync -EnrollmentId $enrollment.Id }
        catch { $syncState = 'Failed'; Write-IRTLog "Sync task start failed: $_" 'WARN' }
    }

    Exit-Script 0 "Fixed | Enrollment=$($enrollment.Id); Reference=Written; Thumbprint=$expectedThumb; SearchCriteria=$criteriaState; Sync=$syncState"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
