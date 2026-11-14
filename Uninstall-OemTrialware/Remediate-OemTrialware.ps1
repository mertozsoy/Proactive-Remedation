<#
.SYNOPSIS
  Remediation script for selected OEM trialware installed through MSI.

.DESCRIPTION
  Uninstalls matching MSI products with reboot suppression and verifies removal. Security product removal requires explicit approval. Non-MSI registrations remain reported. Exits 0 only when no selected registrations remain.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$AllowSecuritySoftwareRemoval = $false
$TargetNames = @('HP Wolf Security', 'HP Wolf Security Application Support', 'HP Security Update Service', 'McAfee', 'McAfee LiveSafe', 'McAfee Total Protection', 'WebAdvisor by McAfee', 'Dell SupportAssist', 'Dell SupportAssist Remediation')
$ExcludedProductCodes = @()
$MaxProductsPerRun = 3
$InstallerTimeoutSeconds = 180
$VerificationSeconds = 20

$PackageName = 'OemTrialware'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-TargetProduct {
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
            $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ($TargetNames -notcontains [string]$entry.DisplayName) { continue }
            if ($ExcludedProductCodes -contains $key.PSChildName) { continue }
            $isMsi = $entry.WindowsInstaller -eq 1 -and $key.PSChildName -match '^\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}$'
            [pscustomobject]@{
                Name = [string]$entry.DisplayName
                ProductCode = $key.PSChildName
                IsMsi = $isMsi
                Security = [string]$entry.DisplayName -notlike 'Dell SupportAssist*'
            }
        }
    }
}

try {
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    $products = @(Get-TargetProduct)
    if ($products.Count -eq 0) { Exit-Script 0 'Healthy | Targets=0' }
    if (-not $EnableRemediation) { Exit-Script 1 "Blocked | Reason=RemediationDisabled; Remaining=$($products.Count)" }
    if ($MaxProductsPerRun -lt 1 -or $InstallerTimeoutSeconds -lt 1 -or $VerificationSeconds -lt 0) {
        Exit-Script 1 'Failed | Reason=InvalidConfiguration'
    }
    $attempted = 0
    $errors = 0
    $rebootRequired = $false
    $eligible = @($products | Where-Object { $_.IsMsi -and (-not $_.Security -or $AllowSecuritySoftwareRemoval) } | Sort-Object ProductCode -Unique)
    foreach ($product in $eligible) {
        if ($attempted -ge $MaxProductsPerRun) { break }
        $attempted++
        $arguments = '/x {0} /qn /norestart REBOOT=ReallySuppress' -f $product.ProductCode
        Write-IRTLog "Uninstall | Product=$($product.ProductCode); App=$($product.Name)"
        $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList $arguments -PassThru -ErrorAction Stop
        if (-not $process.WaitForExit($InstallerTimeoutSeconds * 1000)) {
            $process.Dispose()
            Exit-Script 1 "Failed | Reason=InstallerTimeout; Attempted=$attempted; Action=DoNotStartAnotherInstaller"
        }
        $process.WaitForExit()
        $installerCode = $process.ExitCode
        $process.Dispose()
        Write-IRTLog "Installer | Product=$($product.ProductCode); ExitCode=$installerCode"
        if ($installerCode -eq 3010) { $rebootRequired = $true }
        elseif ($installerCode -ne 0 -and $installerCode -ne 1605 -and $installerCode -ne 1614) { $errors++ }
        if ($installerCode -eq 1618) { break }
    }
    $deadline = (Get-Date).AddSeconds($VerificationSeconds)
    do {
        $remaining = @(Get-TargetProduct)
        if ($remaining.Count -eq 0 -or (Get-Date) -ge $deadline -or $attempted -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ($true)
    if ($remaining.Count -eq 0 -and $errors -eq 0) {
        Exit-Script 0 "Fixed | Remaining=0; Attempted=$attempted; RebootRequired=$rebootRequired"
    }
    $nonMsi = @($remaining | Where-Object { -not $_.IsMsi }).Count
    $blocked = @($remaining | Where-Object { $_.Security -and -not $AllowSecuritySoftwareRemoval }).Count
    Exit-Script 1 "Failed | Remaining=$($remaining.Count); Attempted=$attempted; NonMsi=$nonMsi; SecurityBlocked=$blocked; InstallerErrors=$errors; RebootRequired=$rebootRequired"
}
catch { Exit-Script 1 "Error: Failed | Reason=RemediationError; Type=$($_.Exception.GetType().Name)" }
