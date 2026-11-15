<#
.SYNOPSIS
  Remediation script that enables the WinVerifyTrust EnableCertPaddingCheck setting.

.DESCRIPTION
  Writes EnableCertPaddingCheck as REG_SZ 1 under HKLM\SOFTWARE\Microsoft\Cryptography\Wintrust\Config and, on 64-bit Windows, under HKLM\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config. The existing key is exported to %ProgramData%\IntuneRemediations\Backup before the value is written. Verifies both locations and exits 0 only when the value reads 1, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$NativeKey        = 'HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config'
$Wow6432Key       = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
$ValueName        = 'EnableCertPaddingCheck'
$EnableRemediation   = $true
$IncludeWow6432Node  = $true

$BackupRoot = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'CertPaddingCheck'
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

function Get-PaddingValue {
    param([string]$KeyPath)
    if (-not (Test-Path -LiteralPath $KeyPath)) { return 'Missing' }
    $item = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction Stop
    $prop = $item.PSObject.Properties[$ValueName]
    if ($null -eq $prop) { return 'Missing' }
    $raw = [string]$prop.Value
    if ($raw -eq '1') { return '1' }
    if ($raw -eq '0') { return '0' }
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'Empty' }
    return 'Other'
}

function Export-KeyBackup {
    param([string]$RegPath, [string]$Label)
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    }
    $file = Join-Path $BackupRoot ('CertPaddingCheck-{0}-{1}.reg' -f $Label, [guid]::NewGuid().ToString('N'))
    & reg.exe export $RegPath $file /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-IRTLog "reg export failed for $Label with exit code $LASTEXITCODE" 'WARN'
        return $null
    }
    return $file
}

function Set-PaddingValue {
    param([string]$KeyPath, [string]$RegPath, [string]$Label)
    $backup = $null
    if (Test-Path -LiteralPath $KeyPath) {
        $backup = Export-KeyBackup -RegPath $RegPath -Label $Label
        if ($null -eq $backup) { return [pscustomobject]@{ Ok = $false; Backup = $null } }
    }
    if (-not (Test-Path -LiteralPath $KeyPath)) {
        $null = New-Item -Path $KeyPath -Force -ErrorAction Stop
    }
    Set-ItemProperty -LiteralPath $KeyPath -Name $ValueName -Value '1' -Type String -ErrorAction Stop
    Write-IRTLog "$Label value written as REG_SZ 1"
    return [pscustomobject]@{ Ok = $true; Backup = $backup }
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 ('NotApplicable | ProductType=' + $os.ProductType) }

    $is64 = [Environment]::Is64BitOperatingSystem
    $native = Get-PaddingValue -KeyPath $NativeKey
    $wow = 'Skipped'
    if ($is64) { $wow = Get-PaddingValue -KeyPath $Wow6432Key }

    if (-not $EnableRemediation) {
        Exit-Script 0 ('ReportOnly | Native=' + $native + '; Wow6432=' + $wow)
    }
    if ($native -eq '1' -and (-not $is64 -or $wow -eq '1')) {
        Exit-Script 0 ('Healthy | Native=' + $native + '; Wow6432=' + $wow)
    }

    $failed = @()
    $backedUp = $false

    if ($native -ne '1') {
        $result = Set-PaddingValue -KeyPath $NativeKey -RegPath 'HKLM\SOFTWARE\Microsoft\Cryptography\Wintrust\Config' -Label 'Native'
        if (-not $result.Ok) { $failed += 'Native' }
        elseif ($null -ne $result.Backup) { $backedUp = $true }
    }

    if ($is64 -and $IncludeWow6432Node -and $wow -ne '1') {
        $result = Set-PaddingValue -KeyPath $Wow6432Key -RegPath 'HKLM\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config' -Label 'Wow6432'
        if (-not $result.Ok) { $failed += 'Wow6432' }
        elseif ($null -ne $result.Backup) { $backedUp = $true }
    }

    $finalNative = Get-PaddingValue -KeyPath $NativeKey
    $finalWow = 'Skipped'
    if ($is64) { $finalWow = Get-PaddingValue -KeyPath $Wow6432Key }
    $text = 'Native=' + $finalNative + '; Wow6432=' + $finalWow
    if ($backedUp) { $text += '; Backup=%ProgramData%\IntuneRemediations\Backup' }
    if ($failed.Count -gt 0) { $text += '; Failed=' + ($failed -join '/') }

    if ($finalNative -eq '1' -and (-not $is64 -or $finalWow -eq '1')) {
        Exit-Script 0 ('Fixed | ' + $text)
    }
    Exit-Script 1 ('Failed | ' + $text)
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
