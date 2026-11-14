<#
.SYNOPSIS
  Remediation script for disabled Windows Update services.

.DESCRIPTION
  Restores disabled services to configurable recovery startup types through Service Control Manager.
  Preserves enabled modes and policy-defined services. Exits 0 after verification or 1 if unresolved.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$RecoveryStartupTypes = [ordered]@{
    wuauserv = 'Manual'
    UsoSvc = 'Manual'
    BITS = 'Manual'
    WaaSMedicSvc = 'Manual'
}
$PolicyManagedServices = @()

$PackageName = 'WindowsUpdateServiceStart'
$Phase = 'Remediate'
$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function Get-ServicePolicyNames {
    $directory = Join-Path $env:ProgramData 'IntuneRemediations\WindowsUpdateServiceStart'
    $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
    $id = [guid]::NewGuid().ToString('N')
    $configuration = Join-Path $directory "$id.inf"
    $exportLog = Join-Path $directory "$id.log"
    try {
        $secedit = Join-Path $env:SystemRoot 'System32\secedit.exe'
        & $secedit /export /mergedpolicy /cfg $configuration /areas SERVICES /log $exportLog /quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $configuration)) {
            throw 'ServicePolicyExportFailed'
        }
        $lines = @(Get-Content -LiteralPath $configuration -ErrorAction Stop)
        if ($lines.Count -eq 0) { throw 'ServicePolicyExportEmpty' }
        $inSection = $false
        foreach ($line in $lines) {
            $text = $line.Trim()
            if ($text -match '^\[(.+)\]$') {
                $inSection = $Matches[1] -eq 'Service General Setting'
                continue
            }
            if (-not $inSection -or $text.Length -eq 0 -or $text.StartsWith(';')) { continue }
            if ($text -notmatch '^"?([^",]+)"?\s*,\s*[234]\s*,') {
                throw 'ServicePolicyFormatUnknown'
            }
            $Matches[1].Trim()
        }
    }
    finally {
        foreach ($file in @($configuration, $exportLog)) {
            if (Test-Path -LiteralPath $file) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 17763) {
        Exit-Script 0 'NotApplicable | Reason=RequiresWindowsClient1809OrLater'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -ne 'S-1-5-18' -or -not [Environment]::Is64BitProcess) {
        Exit-Script 1 'Failed | Reason=RequiresSystemAnd64BitPowerShell'
    }
    $disabled = @()
    $missing = @()
    foreach ($name in $RecoveryStartupTypes.Keys) {
        if ($RecoveryStartupTypes[$name] -notin @('Manual', 'Automatic')) { throw 'InvalidRecoveryStartupType' }
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
        if ($null -eq $service) { $missing += $name }
        elseif ($service.StartMode -eq 'Disabled') { $disabled += $name }
    }
    if ($disabled.Count -eq 0 -and $missing.Count -eq 0) {
        Exit-Script 0 'Healthy | Disabled=0; Missing=0; Scope=StartupOnly'
    }
    $managed = @(Get-ServicePolicyNames) + $PolicyManagedServices
    $fixed = @()
    $blocked = @()
    $failed = @()
    foreach ($name in $disabled) {
        if ($managed -contains $name) {
            $blocked += $name
            Write-IRTLog "PolicyManaged | Service=$name" 'WARN'
            continue
        }
        try {
            $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
            if ($null -eq $service) { throw 'ServiceDisappeared' }
            if ($service.StartMode -ne 'Disabled') { continue }
            Set-Service -Name $name -StartupType $RecoveryStartupTypes[$name] -ErrorAction Stop
            $verified = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
            $expected = if ($RecoveryStartupTypes[$name] -eq 'Automatic') { 'Auto' } else { 'Manual' }
            if ($null -eq $verified -or $verified.StartMode -ne $expected) { throw 'StartupVerificationFailed' }
            $fixed += $name
            Write-IRTLog "Fixed | Service=$name; Startup=$expected"
        }
        catch {
            $failed += $name
            Write-IRTLog "Failed | Service=$name; HResult=$($_.Exception.HResult)" 'ERROR'
        }
    }
    $remaining = @()
    foreach ($name in $RecoveryStartupTypes.Keys) {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
        if ($null -eq $service -or $service.StartMode -notin @('Auto', 'Manual')) { $remaining += $name }
    }
    $summary = "Fixed=$($fixed -join ','); PolicyManaged=$($blocked -join ','); Failed=$($failed -join ','); Missing=$($missing -join ','); Remaining=$($remaining -join ',')"
    if ($remaining.Count -gt 0 -or $failed.Count -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
