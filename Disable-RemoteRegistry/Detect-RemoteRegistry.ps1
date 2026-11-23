<#
.SYNOPSIS
  Detection script for the Remote Registry service on managed clients.

.DESCRIPTION
  Reads the start type and the state of the RemoteRegistry service. Exits 1 if the service is not disabled or is running, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$ServiceName   = 'RemoteRegistry'
$ServiceKey    = 'HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry'
$ExpectedStart = 4

$PackageName = 'RemoteRegistry'
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

function Get-StartTypeText { param($Value)
    if ($null -eq $Value) { return 'Unknown' }
    switch ([int]$Value) {
        0 { return 'Boot' }
        1 { return 'System' }
        2 { return 'Automatic' }
        3 { return 'Manual' }
        4 { return 'Disabled' }
        default { return ('Value{0}' -f $Value) }
    }
}

function Get-RemoteRegistryState {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) { return $null }

    $start = $null
    try { $start = (Get-ItemProperty -LiteralPath $ServiceKey -Name 'Start' -ErrorAction Stop).Start } catch { $start = $null }

    [pscustomobject]@{
        StartValue = $start
        StartType  = (Get-StartTypeText $start)
        Status     = [string]$service.Status
    }
}

try {
    $productType = 1
    try { $productType = [int](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).ProductType } catch { $productType = 1 }
    if ($productType -ne 1) { Exit-Script 0 'NotApplicable | ProductType=Server' }

    $state = Get-RemoteRegistryState
    if ($null -eq $state) { Exit-Script 0 'NotApplicable | Service=RemoteRegistry; Reason=NotFound' }

    $summary = 'Service={0}; Start={1}; State={2}' -f $ServiceName, $state.StartType, $state.Status
    if ($null -eq $state.StartValue -or [int]$state.StartValue -ne $ExpectedStart -or $state.Status -eq 'Running') {
        Exit-Script 1 "Drift | $summary"
    }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
