<#
.SYNOPSIS
  Detection script for stopped or disabled Windows Audio services.

.DESCRIPTION
  Reads the Windows Audio and Windows Audio Endpoint Builder services from CIM and counts present audio endpoints.
  Exits 1 if a service is disabled or not running, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$AudioServices  = @('AudioEndpointBuilder', 'Audiosrv')
$CheckEndpoints = $true

$PackageName = 'AudioServices'
$Phase       = 'Detect'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-AudioServiceState {
    $result = @()
    foreach ($name in $AudioServices) {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            $result += [pscustomobject]@{ Name = $name; State = 'Missing'; StartMode = 'Missing' }
            continue
        }
        $result += [pscustomobject]@{
            Name      = $name
            State     = [string]$service.State
            StartMode = [string]$service.StartMode
        }
    }
    $result
}

function Get-AudioEndpointCount {
    try { return @(Get-PnpDevice -Class 'AudioEndpoint' -PresentOnly -ErrorAction Stop).Count }
    catch { return -1 }
}

try {
    $states  = @(Get-AudioServiceState)
    $present = @($states | Where-Object { $_.State -ne 'Missing' })
    if ($present.Count -ne $states.Count) {
        $missing = (@($states | Where-Object { $_.State -eq 'Missing' } | ForEach-Object { $_.Name }) -join ',')
        Exit-Script 0 "NotApplicable | Reason=ServiceMissing; Services=$missing"
    }

    $endpoints = 'Skipped'
    if ($CheckEndpoints) { $endpoints = Get-AudioEndpointCount }

    $detail = (@($states | ForEach-Object { '{0}={1}/{2}' -f $_.Name, $_.State, $_.StartMode }) -join '; ')
    $drift  = @($states | Where-Object { $_.StartMode -eq 'Disabled' -or $_.State -ne 'Running' })
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | $detail; Endpoints=$endpoints" }

    $services = (@($drift | ForEach-Object { $_.Name }) -join ',')
    Exit-Script 1 "Drift | $detail; Endpoints=$endpoints; Services=$services"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
