<#
.SYNOPSIS
  Remediation script that blocks personal Workplace Join on the device.

.DESCRIPTION
  Writes BlockAADWorkplaceJoin as a DWORD with value 1 under HKLM\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin. The existing key is exported to %ProgramData%\IntuneRemediations\Backup\WorkplaceJoin before the value is written. Re-reads the value and exits 0 only when it reads 1, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnableRemediation = $true
$PolicyKey         = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
$RegPath           = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
$ValueName         = 'BlockAADWorkplaceJoin'
$ExpectedValue     = 1
$BackupRoot        = Join-Path $env:ProgramData 'IntuneRemediations\Backup\WorkplaceJoin'

$PackageName = 'WorkplaceJoin'
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

function Get-BlockState {
    param([string]$KeyPath, [string]$Name)
    if (-not (Test-Path -LiteralPath $KeyPath)) { return 'Missing' }
    $item = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'Missing' }
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) { return 'Missing' }
    return [string]$property.Value
}

function Export-PolicyBackup {
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        $null = New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop
    }
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $target = Join-Path $BackupRoot ('WorkplaceJoin-{0}.reg' -f $stamp)
    & reg.exe export $RegPath $target /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Write-IRTLog "reg export failed with exit code $LASTEXITCODE" 'WARN'
        return $null
    }
    return $target
}

try {
    $state = Get-BlockState -KeyPath $PolicyKey -Name $ValueName
    $text  = 'BlockAADWorkplaceJoin={0}; Expected={1}' -f $state, $ExpectedValue

    if ($state -eq [string]$ExpectedValue) { Exit-Script 0 "Healthy | $text" }

    if (-not $EnableRemediation) { Exit-Script 0 "ReportOnly | $text; EnableRemediation=false" }

    $backup = 'None'
    if (Test-Path -LiteralPath $PolicyKey) {
        $file = Export-PolicyBackup
        if ($null -eq $file) { Exit-Script 1 "Failed | $text; Backup=Failed" }
        $backup = '%ProgramData%\IntuneRemediations\Backup\WorkplaceJoin'
        Write-IRTLog "Policy key exported to $file"
    }

    if (-not (Test-Path -LiteralPath $PolicyKey)) {
        $null = New-Item -Path $PolicyKey -Force -ErrorAction Stop
        Write-IRTLog "Policy key created"
    }

    Set-ItemProperty -LiteralPath $PolicyKey -Name $ValueName -Value $ExpectedValue -Type DWord -ErrorAction Stop
    Write-IRTLog "BlockAADWorkplaceJoin set to $ExpectedValue, previous value $state"

    $final = Get-BlockState -KeyPath $PolicyKey -Name $ValueName
    $finalText = 'BlockAADWorkplaceJoin={0}; Backup={1}' -f $final, $backup
    if ($final -eq [string]$ExpectedValue) { Exit-Script 0 "Fixed | $finalText" }
    Exit-Script 1 "Failed | $finalText"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
