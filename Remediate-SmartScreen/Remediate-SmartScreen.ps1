<#
.SYNOPSIS
  Remediation script that turns Microsoft Defender SmartScreen back on.

.DESCRIPTION
  Writes EnableSmartScreen=1 to HKLM\SOFTWARE\Policies\Microsoft\Windows\System so SmartScreen applies to every user and the App and browser control toggle cannot be switched off. Turns the Edge policy back on when it is disabled. A disabled policy value is preserved unless the matching opt-in variable is set. Verifies both states and exits 0 only when SmartScreen is on, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$SystemPolicyKey        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$EdgePolicyKey          = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$ExplorerKey            = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
$EnableRemediation      = $true
$EnforceEdgePolicy      = $true
$OverrideDisabledPolicy = $false
$BackupRoot             = Join-Path $env:ProgramData 'IntuneRemediations\Backup'

$PackageName = 'SmartScreen'
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

function Get-ShellSmartScreen {
    $policyValue = $null
    if (Test-Path -LiteralPath $SystemPolicyKey) {
        $item = Get-ItemProperty -LiteralPath $SystemPolicyKey -ErrorAction Stop
        if ($null -ne $item.EnableSmartScreen) { $policyValue = [int]$item.EnableSmartScreen }
    }

    $uiValue = $null
    if (Test-Path -LiteralPath $ExplorerKey) {
        $item = Get-ItemProperty -LiteralPath $ExplorerKey -ErrorAction Stop
        if ($null -ne $item.SmartScreenEnabled) { $uiValue = [string]$item.SmartScreenEnabled }
    }

    $source = 'Default'
    $on     = $true
    if ($null -ne $policyValue) {
        $source = 'Policy'
        $on     = ($policyValue -ne 0)
    }
    elseif ($null -ne $uiValue) {
        $source = 'DeviceUI'
        $on     = ($uiValue -ne 'Off')
    }

    [pscustomobject]@{ On = $on; Source = $source; PolicyValue = $policyValue; UiValue = $uiValue }
}

function Get-EdgeSmartScreen {
    $edgeValue = $null
    if (Test-Path -LiteralPath $EdgePolicyKey) {
        $item = Get-ItemProperty -LiteralPath $EdgePolicyKey -ErrorAction Stop
        if ($null -ne $item.SmartScreenEnabled) { $edgeValue = [int]$item.SmartScreenEnabled }
    }

    if ($null -eq $edgeValue) {
        return [pscustomobject]@{ On = $true; Source = 'Default'; PolicyValue = $null }
    }
    [pscustomobject]@{ On = ($edgeValue -ne 0); Source = 'Policy'; PolicyValue = $edgeValue }
}

function Format-State {
    param($Shell, $Edge)
    $shellText = 'On'
    if (-not $Shell.On) { $shellText = 'Off(' + $Shell.Source + ')' }
    $edgeText = 'On'
    if (-not $Edge.On) { $edgeText = 'Off(' + $Edge.Source + ')' }
    'Shell=' + $shellText + '; Edge=' + $edgeText
}

function Export-PolicyBackup {
    param([string]$RegPath, [string]$Label)
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    }
    $file = Join-Path $BackupRoot ('SmartScreen-{0}-{1}.reg' -f $Label, [guid]::NewGuid().ToString('N'))
    & reg.exe export $RegPath $file /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-IRTLog "reg export failed for $Label with exit code $LASTEXITCODE" 'WARN'
        return $null
    }
    $file
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 ('NotApplicable | ProductType=' + $os.ProductType) }

    $shell = Get-ShellSmartScreen
    $edge  = Get-EdgeSmartScreen
    if (-not $EnableRemediation) {
        Exit-Script 0 ('ReportOnly | ' + (Format-State -Shell $shell -Edge $edge))
    }
    if ($shell.On -and $edge.On) {
        Exit-Script 0 ('Healthy | ' + (Format-State -Shell $shell -Edge $edge))
    }

    $backups = @()
    $blocked = @()

    if (-not $shell.On) {
        if ($shell.Source -eq 'Policy' -and -not $OverrideDisabledPolicy) {
            $blocked += 'Shell'
            Write-IRTLog 'EnableSmartScreen policy value is 0 and OverrideDisabledPolicy is off'
        }
        else {
            if ($shell.Source -eq 'Policy') {
                $backup = Export-PolicyBackup -RegPath 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' -Label 'Shell'
                if ($null -eq $backup) { $blocked += 'Shell' }
                else { $backups += $backup }
            }
            if ($blocked -notcontains 'Shell') {
                if (-not (Test-Path -LiteralPath $SystemPolicyKey)) {
                    $null = New-Item -Path $SystemPolicyKey -Force -ErrorAction Stop
                }
                Set-ItemProperty -LiteralPath $SystemPolicyKey -Name 'EnableSmartScreen' -Value 1 -Type DWord -ErrorAction Stop
                Write-IRTLog 'EnableSmartScreen policy value set to 1'
            }
        }
    }

    if (-not $edge.On) {
        if (-not $EnforceEdgePolicy) {
            $blocked += 'Edge'
            Write-IRTLog 'Edge SmartScreenEnabled policy value is 0 and EnforceEdgePolicy is off'
        }
        else {
            $backup = Export-PolicyBackup -RegPath 'HKLM\SOFTWARE\Policies\Microsoft\Edge' -Label 'Edge'
            if ($null -eq $backup) {
                $blocked += 'Edge'
            }
            else {
                $backups += $backup
                Set-ItemProperty -LiteralPath $EdgePolicyKey -Name 'SmartScreenEnabled' -Value 1 -Type DWord -ErrorAction Stop
                Write-IRTLog 'Edge SmartScreenEnabled policy value set to 1'
            }
        }
    }

    $finalShell = Get-ShellSmartScreen
    $finalEdge  = Get-EdgeSmartScreen
    $text       = Format-State -Shell $finalShell -Edge $finalEdge
    $detail     = ''
    if ($blocked.Count -gt 0) { $detail += '; Preserved=' + ($blocked -join '/') }
    if ($backups.Count -gt 0) { $detail += '; Backup=%ProgramData%\IntuneRemediations\Backup' }

    if ($finalShell.On -and $finalEdge.On) { Exit-Script 0 ('Fixed | ' + $text + $detail) }
    Exit-Script 1 ('Failed | ' + $text + $detail)
}
catch { Exit-Script 1 ('Error | Detail=' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }
