<#
.SYNOPSIS
  Remediation script for stopped or disabled Windows Audio services.

.DESCRIPTION
  Restores the Windows Audio and Windows Audio Endpoint Builder services to Automatic, starts them and verifies
  that both run. Skips services managed by a service security policy. Exits 0 when both services run, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AudioServices          = @('AudioEndpointBuilder', 'Audiosrv')
$RecoveryStartupType    = 'Automatic'
$RestartEndpointBuilder = $false

$PackageName     = 'AudioServices'
$Phase           = 'Remediate'
$LogFile         = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
$BackupDirectory = Join-Path $env:ProgramData 'IntuneRemediations\Backup'
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-PolicyManagedService {
    $directory = Join-Path $env:ProgramData 'IntuneRemediations\AudioServices'
    $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
    $id            = [guid]::NewGuid().ToString('N')
    $configuration = Join-Path $directory "$id.inf"
    $exportLog     = Join-Path $directory "$id.log"
    try {
        $secedit = Join-Path $env:SystemRoot 'System32\secedit.exe'
        & $secedit /export /mergedpolicy /cfg $configuration /areas SERVICES /log $exportLog /quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $configuration)) { return @() }
        $names     = @()
        $inSection = $false
        foreach ($line in @(Get-Content -LiteralPath $configuration -ErrorAction Stop)) {
            $text = $line.Trim()
            if ($text -match '^\[(.+)\]$') { $inSection = $Matches[1] -eq 'Service General Setting'; continue }
            if (-not $inSection -or $text.Length -eq 0 -or $text.StartsWith(';')) { continue }
            if ($text -notmatch '^"?([^",]+)"?\s*,\s*[234]\s*,') { continue }
            $names += $Matches[1].Trim()
        }
        return $names
    }
    catch { return @() }
    finally {
        foreach ($file in @($configuration, $exportLog)) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Backup-ServiceKey { param([string]$Name)
    $null = New-Item -Path $BackupDirectory -ItemType Directory -Force -ErrorAction Stop
    $file = Join-Path $BackupDirectory ('{0}_{1}.reg' -f $Name, (Get-Date -Format 'yyyyMMddHHmmss'))
    $reg  = Join-Path $env:SystemRoot 'System32\reg.exe'
    & $reg export "HKLM\SYSTEM\CurrentControlSet\Services\$Name" $file /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'ServiceKeyBackupFailed' }
    return $file
}

function Get-AudioEndpointCount {
    try { return @(Get-PnpDevice -Class 'AudioEndpoint' -PresentOnly -ErrorAction Stop).Count }
    catch { return -1 }
}

try {
    if ($RecoveryStartupType -notin @('Automatic', 'Manual')) { throw 'InvalidRecoveryStartupType' }

    $states = @()
    foreach ($name in $AudioServices) {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if ($null -eq $service) { $states += [pscustomobject]@{ Name = $name; State = 'Missing' } }
        else { $states += [pscustomobject]@{ Name = $name; State = [string]$service.State } }
    }
    $missing = @($states | Where-Object { $_.State -eq 'Missing' })
    if ($missing.Count -eq $states.Count) { Exit-Script 0 'NotApplicable | Reason=AudioServicesNotFound' }
    if ($missing.Count -gt 0) {
        $names = (@($missing | ForEach-Object { $_.Name }) -join ',')
        Exit-Script 0 "NotApplicable | Reason=ServiceMissing; Services=$names"
    }

    $policyManaged = @(Get-PolicyManagedService)
    $blocked = @()
    $failed  = @()

    foreach ($name in $AudioServices) {
        if ($policyManaged -contains $name) {
            $blocked += $name
            Write-IRTLog "PolicyManaged | Service=$name" 'WARN'
            continue
        }
        try {
            $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
            if ($null -eq $service) { throw 'ServiceDisappeared' }
            if ($service.StartMode -eq 'Disabled') {
                $backup = Backup-ServiceKey -Name $name
                Set-Service -Name $name -StartupType $RecoveryStartupType -ErrorAction Stop
                Write-IRTLog "StartupRestored | Service=$name; Startup=$RecoveryStartupType; Backup=$backup"
            }
            if ((Get-Service -Name $name -ErrorAction Stop).Status -ne 'Running') {
                Start-Service -Name $name -ErrorAction Stop
                Write-IRTLog "Started | Service=$name"
            }
        }
        catch {
            $failed += $name
            $exitCode = 'Unknown'
            $current  = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
            if ($null -ne $current) { $exitCode = $current.ExitCode }
            Write-IRTLog "Failed | Service=$name; HResult=$($_.Exception.HResult); ServiceExitCode=$exitCode" 'ERROR'
        }
    }

    $endpoints = Get-AudioEndpointCount
    if ($RestartEndpointBuilder -and $endpoints -eq 0) {
        try {
            Restart-Service -Name 'AudioEndpointBuilder' -Force -ErrorAction Stop
            Start-Sleep -Seconds 3
            $endpoints = Get-AudioEndpointCount
            Write-IRTLog "EndpointBuilderRestarted | Endpoints=$endpoints"
        }
        catch {
            $failed += 'EndpointBuilderRestart'
            Write-IRTLog "Failed | Operation=EndpointBuilderRestart; HResult=$($_.Exception.HResult)" 'ERROR'
        }
    }

    $remaining = @()
    $detail    = @()
    foreach ($name in $AudioServices) {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
        if ($null -eq $service) {
            $remaining += $name
            $detail += ('{0}=Missing' -f $name)
            continue
        }
        if ($service.State -ne 'Running' -or $service.StartMode -eq 'Disabled') { $remaining += $name }
        $detail += ('{0}={1}/{2}' -f $name, $service.State, $service.StartMode)
    }

    $summary = ($detail -join '; ') + "; Endpoints=$endpoints"
    if ($blocked.Count -gt 0) { $summary += "; PolicyManaged=$($blocked -join ',')" }
    if ($failed.Count -gt 0) { $summary += "; Failed=$($failed -join ',')" }
    if ($remaining.Count -gt 0 -or $failed.Count -gt 0) { Exit-Script 1 "Failed | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
