<#
.SYNOPSIS
  Remediation script that puts Microsoft Defender network protection in block mode.

.DESCRIPTION
  Reads the effective state, sets block mode with Set-MpPreference and reads the state back. A value owned by Group Policy or Intune policy is left untouched unless OverridePolicy is enabled. Registry writes are exported to a backup folder first. Exits 0 when block mode is active, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$MinimumBuild      = 16299
$ExpectedState     = 1
$EnableRemediation = $true
$OverridePolicy    = $false
$ValueName         = 'EnableNetworkProtection'
$PolicyKey         = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection'
$MdmKey            = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager'
$LocalKey          = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection'
$PassiveAvModes    = @('Passive', 'SxS Passive Mode')
$BackupRoot        = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'DefenderNetworkProtection'
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

function Get-RegistryState {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    if ($null -eq $item.PSObject.Properties[$Name]) { return $null }
    [int]$item.$Name
}

function Get-ProtectionState {
    $preference = Get-MpPreference -ErrorAction Stop
    $effective  = $null
    if ($null -ne $preference.EnableNetworkProtection) { $effective = [int]$preference.EnableNetworkProtection }

    $policyValue = Get-RegistryState -Path $PolicyKey -Name $ValueName
    $mdmValue    = Get-RegistryState -Path $MdmKey -Name $ValueName

    $source = 'Local'
    if ($null -ne $policyValue) { $source = 'Policy' }
    elseif ($null -ne $mdmValue) { $source = 'MDM' }

    [pscustomobject]@{ Effective = $effective; Source = $source; PolicyValue = $policyValue; MdmValue = $mdmValue }
}

function Format-State {
    param($State)
    $text = 'Off(0)'
    if ($State.Effective -eq 1) { $text = 'Block(1)' }
    elseif ($State.Effective -eq 2) { $text = 'Audit(2)' }
    'State=' + $text + '; Source=' + $State.Source
}

function Export-RegistryBackup {
    param([string]$RegPath, [string]$Label)
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    }
    $file = Join-Path $BackupRoot ('NetworkProtection-{0}-{1}.reg' -f $Label, [guid]::NewGuid().ToString('N'))
    & reg.exe export $RegPath $file /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-IRTLog "reg export failed for $Label with exit code $LASTEXITCODE" 'WARN'
        return $null
    }
    $file
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt $MinimumBuild) {
        Exit-Script 0 'NotApplicable | Requires=Windows10-1709OrLaterClient'
    }

    $avMode = $null
    try { $avMode = [string](Get-MpComputerStatus -ErrorAction Stop).AMRunningMode } catch { $avMode = $null }
    if ([string]::IsNullOrWhiteSpace($avMode)) { Exit-Script 0 'NotApplicable | DefenderStatusUnavailable' }
    if ($PassiveAvModes -contains $avMode) { Exit-Script 0 ('NotApplicable | AvMode=' + $avMode) }

    $state = $null
    try { $state = Get-ProtectionState } catch { $state = $null }
    if ($null -eq $state -or $null -eq $state.Effective) {
        Exit-Script 0 'NotApplicable | EnableNetworkProtection not reported'
    }

    $text = Format-State -State $state
    if (-not $EnableRemediation) { Exit-Script 0 ('ReportOnly | ' + $text) }
    if ($state.Effective -eq $ExpectedState) { Exit-Script 0 ('Healthy | ' + $text) }

    $action  = 'None'
    $detail  = ''
    $blocked = $false

    if ($state.Source -eq 'MDM') {
        $blocked = $true
        Write-IRTLog 'Value is owned by the Intune policy registry path; no write'
    }
    elseif ($state.Source -eq 'Policy' -and -not $OverridePolicy) {
        $blocked = $true
        Write-IRTLog 'Value is owned by Group Policy and OverridePolicy is off'
    }
    elseif ($state.Source -eq 'Policy') {
        $backup = Export-RegistryBackup -RegPath 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection' -Label 'Policy'
        if ($null -eq $backup) {
            $blocked = $true
        }
        else {
            if (-not (Test-Path -LiteralPath $PolicyKey)) { $null = New-Item -Path $PolicyKey -Force -ErrorAction Stop }
            Set-ItemProperty -LiteralPath $PolicyKey -Name $ValueName -Value $ExpectedState -Type DWord -ErrorAction Stop
            Write-IRTLog 'Group Policy value set to block mode'
            $action = 'PolicyValue'
            $detail = '; Backup=%ProgramData%\IntuneRemediations\Backup'
        }
    }
    else {
        $action = 'MpPreference'
        try { $null = Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction Stop }
        catch { Write-IRTLog ('Set-MpPreference returned an error: ' + $_.Exception.Message) 'WARN' }
    }

    $final = Get-ProtectionState

    if ($action -eq 'MpPreference' -and $final.Effective -ne $ExpectedState) {
        $localBackup = 'NoKey'
        if (Test-Path -LiteralPath $LocalKey) {
            $localBackup = Export-RegistryBackup -RegPath 'HKLM\SOFTWARE\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection' -Label 'Local'
        }
        if ($null -ne $localBackup) {
            if (-not (Test-Path -LiteralPath $LocalKey)) { $null = New-Item -Path $LocalKey -Force -ErrorAction Stop }
            Set-ItemProperty -LiteralPath $LocalKey -Name $ValueName -Value $ExpectedState -Type DWord -ErrorAction Stop
            Write-IRTLog 'Local network protection value set to block mode'
            $action = 'LocalValue'
            $detail = '; Backup=%ProgramData%\IntuneRemediations\Backup'
            $final  = Get-ProtectionState
        }
    }

    $text = Format-State -State $final
    if ($final.Effective -eq $ExpectedState) { Exit-Script 0 ('Fixed | ' + $text + $detail) }
    if ($action -eq 'PolicyValue' -and $final.PolicyValue -eq $ExpectedState) {
        Exit-Script 0 ('Fixed | ' + $text + '; Apply=NextPolicyRefresh' + $detail)
    }
    if ($blocked) { Exit-Script 1 ('Failed | ' + $text + '; Reason=PolicyManaged') }
    Exit-Script 1 ('Failed | ' + $text + '; Action=' + $action)
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
