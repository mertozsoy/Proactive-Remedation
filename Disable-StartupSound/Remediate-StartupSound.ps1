<#
.SYNOPSIS
  Remediation script that turns off the Windows startup sound.

.DESCRIPTION
  Backs up the policy key and writes the startup sound policy value so the sound stays off for every user. Exits 0 when the value is in place, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$PolicyKey         = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$PolicyRegPath     = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$PolicyValue       = 'DisableStartupSound'
$SettingKey        = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation'
$SettingValue      = 'DisableStartupSound'
$BackupDir         = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'StartupSound'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

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

function Get-RegValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($item.PSObject.Properties.Name -notcontains $Name) { return $null }
    return [int]$item.$Name
}

function Format-RegValue {
    param($Value)
    if ($null -eq $Value) { return 'NotSet' }
    if ($Value -eq 1) { return 'Off' }
    if ($Value -eq 0) { return 'On' }
    return [string]$Value
}

function Backup-RegistryKey {
    param([string]$KeyPath, [string]$FileName)
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        $null = New-Item -ItemType Directory -Path $BackupDir -Force -ErrorAction Stop
    }
    $file = Join-Path $BackupDir $FileName
    $null = & reg.exe export $KeyPath $file /y 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-IRTLog "Registry export failed for $KeyPath" 'WARN'
        return ''
    }
    return $FileName
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | OS=Server' }

    $policy      = Get-RegValue -Path $PolicyKey -Name $PolicyValue
    $setting     = Get-RegValue -Path $SettingKey -Name $SettingValue
    $settingText = Format-RegValue -Value $setting

    if ($policy -eq 0) { Exit-Script 0 "Skipped | Policy=ForcedOn; Setting=$settingText; Action=ReportedOnly" }
    if ($policy -eq 1) { Exit-Script 0 "Healthy | Policy=Off; Setting=$settingText" }
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Policy=NotSet; Setting=$settingText; EnableRemediation=false" }

    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Backup-RegistryKey -KeyPath $PolicyRegPath -FileName "StartupSound_$stamp.reg"

    if (-not (Test-Path -LiteralPath $PolicyKey)) {
        $null = New-Item -Path $PolicyKey -Force -ErrorAction Stop
    }
    $null = New-ItemProperty -LiteralPath $PolicyKey -Name $PolicyValue -PropertyType DWord -Value 1 -Force -ErrorAction Stop
    Write-IRTLog "Policy value $PolicyValue set to 1"

    $policy      = Get-RegValue -Path $PolicyKey -Name $PolicyValue
    $setting     = Get-RegValue -Path $SettingKey -Name $SettingValue
    $settingText = Format-RegValue -Value $setting

    if ($policy -ne 1) {
        $policyText = Format-RegValue -Value $policy
        Exit-Script 1 "Failed | Policy=$policyText; Setting=$settingText"
    }
    if ($backup) { Exit-Script 0 "Fixed | Policy=Off; Setting=$settingText; Backup=$backup" }
    Exit-Script 0 "Fixed | Policy=Off; Setting=$settingText; Backup=None"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
