<#
.SYNOPSIS
  Detection script for a stopped or broken Windows Search index.

.DESCRIPTION
  Reads the WSearch service state, the SearchIndexer process and the index database. Exits 1 when search cannot serve results, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$IndexDirectory = Join-Path $env:ProgramData 'Microsoft\Search\Data\Applications\Windows'
$IndexFileNames = @('Windows.db', 'Windows.edb')

$PackageName = 'SearchIndex'
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
function Get-IndexDatabase {
    foreach ($name in $IndexFileNames) {
        $path = Join-Path $IndexDirectory $name
        if (Test-Path -LiteralPath $path) { return (Get-Item -LiteralPath $path -ErrorAction Stop) }
    }
    return $null
}

try {
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='WSearch'" -ErrorAction Stop
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | WSearch=NotInstalled' }

    $database = Get-IndexDatabase
    $dbSize = [int64]0
    if ($null -ne $database) { $dbSize = [int64]$database.Length }
    $indexer = @(Get-Process -Name 'SearchIndexer' -ErrorAction SilentlyContinue)

    $issues = @()
    if ($service.StartMode -eq 'Disabled') { $issues += 'StartType=Disabled' }
    if ($service.State -ne 'Running') { $issues += 'Service=Stopped' }
    elseif ($indexer.Count -eq 0) { $issues += 'Indexer=NotRunning' }
    if ($null -eq $database -or $dbSize -eq 0) { $issues += 'IndexDb=Missing' }

    if ($issues.Count -gt 0) {
        Exit-Script 1 ("Drift | {0}; Service={1}" -f ($issues -join '; '), $service.State)
    }

    $sizeMb = [math]::Round($dbSize / 1MB, 1)
    Exit-Script 0 ("Healthy | Service=Running; Indexer=Running; IndexDb={0}MB" -f $sizeMb)
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
