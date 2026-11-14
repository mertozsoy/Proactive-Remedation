<#
.SYNOPSIS
  Remediation script for unwanted Office Click-to-Run products.

.DESCRIPTION
  Uses a locally staged and verified Office Deployment Tool to remove explicitly listed products. Preserves other product IDs and verifies the result. Removal requires approval. No language removal or application shutdown is performed.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RemoveProductIds = @('HomeBusiness2021Retail', 'HomeBusiness2024Retail', 'HomeStudent2021Retail', 'Home2024Retail', 'O365HomePremRetail')
$RequiredSuiteIds = @('O365ProPlusRetail', 'O365BusinessRetail', 'O365ProPlusEEANoTeamsRetail', 'O365BusinessEEANoTeamsRetail')
$EnableRemediation = $false
$OdtPath = Join-Path $env:ProgramData 'IntuneRemediations\Tools\OfficeDeploymentTool\setup.exe'
$OdtSha256 = ''
$TimeoutSeconds = 600

$PackageName = 'ExtraOfficeProducts'
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
function Get-OfficeProductId {
    $raw = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -Name ProductReleaseIds -ErrorAction Stop
    $ids = @(([string]$raw -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($ids.Count -eq 0 -or @($ids | Where-Object { $_ -notmatch '^[A-Za-z0-9]+$' }).Count -gt 0) {
        throw 'Invalid product inventory'
    }
    $ids
}

try {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitProcess) { Exit-Script 1 'Failed | Reason=Use64BitPowerShell' }
    if ($TimeoutSeconds -lt 30 -or $TimeoutSeconds -gt 900) { Exit-Script 1 'Failed | Reason=InvalidTimeout' }
    if (@($RemoveProductIds | Where-Object { $_ -notmatch '^[A-Za-z0-9]+$' -or $_ -match '^(O365ProPlus|O365Business|Visio|Project)' -or $RequiredSuiteIds -contains $_ }).Count -gt 0) {
        Exit-Script 1 'Failed | Reason=UnsafeRemovalList'
    }
    if (-not (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration')) {
        Exit-Script 0 'NotApplicable | Reason=NoClickToRun; LanguageAudit=NotCovered'
    }
    $installed = @(Get-OfficeProductId)
    $targets = @($installed | Where-Object { $RemoveProductIds -contains $_ })
    if ($targets.Count -eq 0) { Exit-Script 0 'Healthy | UnwantedProducts=0; LanguageAudit=NotCovered' }
    if (-not $EnableRemediation) { Exit-Script 1 "Blocked | Reason=RemovalNotApproved; Products=$($targets -join ',')" }
    if (@($installed | Where-Object { $RequiredSuiteIds -contains $_ }).Count -eq 0) {
        Exit-Script 1 'Blocked | Reason=RequiredSuiteMissing'
    }
    $busyNames = @('winword', 'excel', 'powerpnt', 'outlook', 'onenote', 'msaccess', 'mspub', 'visio', 'winproj', 'lync', 'groove', 'infopath', 'mstore', 'setlang', 'msouc', 'ois', 'graph', 'teams', 'ms-teams', 'setup', 'OfficeC2RClient', 'integratedoffice')
    $busy = @(Get-Process -ErrorAction Stop | Where-Object { $busyNames -contains $_.ProcessName })
    if ($busy.Count -gt 0) { Exit-Script 1 'Deferred | Reason=OfficeAppsOrInstallerRunning' }
    if ($OdtPath -notmatch '^[A-Za-z]:\\' -or -not (Test-Path -LiteralPath $OdtPath -PathType Leaf)) {
        Exit-Script 1 'Blocked | Reason=LocalOdtMissing'
    }
    if ($OdtSha256 -notmatch '^[A-Fa-f0-9]{64}$') { Exit-Script 1 'Blocked | Reason=ConfigureOdtSha256' }
    $signature = Get-AuthenticodeSignature -LiteralPath $OdtPath -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        Exit-Script 1 'Blocked | Reason=OdtSignatureInvalid'
    }
    if ((Get-FileHash -LiteralPath $OdtPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $OdtSha256) {
        Exit-Script 1 'Blocked | Reason=OdtHashMismatch'
    }
    $preserved = @($installed | Where-Object { $targets -notcontains $_ })
    $workPath = Join-Path $env:ProgramData ('IntuneRemediations\OfficeCleanup\' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $workPath -ItemType Directory -Force -ErrorAction Stop
    $xmlPath = Join-Path $workPath 'remove.xml'
    $xml = New-Object System.Xml.XmlDocument
    $configuration = $xml.CreateElement('Configuration')
    $null = $xml.AppendChild($configuration)
    $remove = $xml.CreateElement('Remove')
    $remove.SetAttribute('All', 'FALSE')
    $null = $configuration.AppendChild($remove)
    foreach ($id in $targets) {
        $product = $xml.CreateElement('Product')
        $product.SetAttribute('ID', $id)
        $null = $remove.AppendChild($product)
    }
    $display = $xml.CreateElement('Display')
    $display.SetAttribute('Level', 'None')
    $display.SetAttribute('AcceptEULA', 'TRUE')
    $null = $configuration.AppendChild($display)
    $shutdown = $xml.CreateElement('Property')
    $shutdown.SetAttribute('Name', 'FORCEAPPSHUTDOWN')
    $shutdown.SetAttribute('Value', 'FALSE')
    $null = $configuration.AppendChild($shutdown)
    $xml.Save($xmlPath)
    Write-IRTLog ('Removing=' + ($targets -join ',') + '; Preserving=' + ($preserved -join ','))
    $process = Start-Process -FilePath $OdtPath -ArgumentList ('/configure "{0}"' -f $xmlPath) -PassThru -ErrorAction Stop
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Exit-Script 1 'Deferred | Reason=OdtTimeout; InstallerLeftRunning=True'
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0) { Exit-Script 1 "Failed | Reason=OdtExitCode; Code=$($process.ExitCode)" }
    $remaining = @()
    $missing = @()
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $after = @(Get-OfficeProductId)
        $remaining = @($after | Where-Object { $RemoveProductIds -contains $_ })
        $missing = @($preserved | Where-Object { $after -notcontains $_ })
        if ($remaining.Count -eq 0 -and $missing.Count -eq 0) { break }
        Start-Sleep -Seconds 5
    }
    if ($remaining.Count -gt 0 -or $missing.Count -gt 0) {
        Exit-Script 1 "Failed | Reason=Verification; Remaining=$($remaining.Count); MissingPreserved=$($missing.Count)"
    }
    Exit-Script 0 "Fixed | RemovedProducts=$($targets.Count); PreservedProducts=$($preserved.Count); LanguageAudit=NotCovered"
}
catch { Exit-Script 1 "Failed | Reason=RemediationError; ErrorType=$($_.Exception.GetType().Name)" }
