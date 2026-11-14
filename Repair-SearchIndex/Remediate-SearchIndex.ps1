<#
.SYNOPSIS
  Remediation script that repairs the Windows Search index.

.DESCRIPTION
  Restores the WSearch start type, starts the service, restarts the search UI and rebuilds the index database when it is missing or empty. Exits 0 when search is healthy, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$EnsureDelayedStart = $true
$ForceRebuild       = $false
$RestartSearchHost  = $true
$BackupRoot         = Join-Path $env:ProgramData 'IntuneRemediations\Backup\SearchIndex'
$IndexDirectory     = Join-Path $env:ProgramData 'Microsoft\Search\Data\Applications\Windows'
$IndexFileNames     = @('Windows.db', 'Windows.edb')

$PackageName = 'SearchIndex'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"

function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
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
function Wait-ServiceState { param([string]$ServiceName, [string]$State, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $current = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
        if ($null -ne $current -and $current.State -eq $State) { return $true }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}
function Test-ServicePolicyManaged { param([string]$ServiceName)
    $directory = Join-Path $env:ProgramData 'IntuneRemediations\SearchIndex'
    $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
    $id = [guid]::NewGuid().ToString('N')
    $configuration = Join-Path $directory "$id.inf"
    $exportLog = Join-Path $directory "$id.log"
    try {
        $secedit = Join-Path $env:SystemRoot 'System32\secedit.exe'
        & $secedit /export /mergedpolicy /cfg $configuration /areas SERVICES /log $exportLog /quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $configuration)) { throw 'ServicePolicyExportFailed' }
        $inSection = $false
        foreach ($line in Get-Content -LiteralPath $configuration -ErrorAction Stop) {
            $text = $line.Trim()
            if ($text -match '^\[(.+)\]$') {
                $inSection = $Matches[1] -eq 'Service General Setting'
                continue
            }
            if (-not $inSection -or $text.Length -eq 0 -or $text.StartsWith(';')) { continue }
            if ($text -match '^"?([^",]+)"?\s*,\s*4\s*,') {
                if ($Matches[1].Trim() -eq $ServiceName) { return $true }
            }
        }
        return $false
    }
    finally {
        foreach ($file in @($configuration, $exportLog)) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        }
    }
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1) { Exit-Script 0 'NotApplicable | RequiresWindowsClient' }

    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='WSearch'" -ErrorAction Stop
    if ($null -eq $service) { Exit-Script 0 'NotApplicable | WSearch=NotInstalled' }

    $actions = @()
    $blocked = @()

    if ($service.StartMode -eq 'Disabled') {
        if (Test-ServicePolicyManaged -ServiceName 'WSearch') {
            $blocked += 'StartType=PolicyManaged'
            Write-IRTLog 'WSearch start type is set by policy, left unchanged' 'WARN'
        }
        else {
            Set-Service -Name 'WSearch' -StartupType Automatic -ErrorAction Stop
            $actions += 'StartType=Automatic'
            if ($EnsureDelayedStart) {
                $sc = Join-Path $env:SystemRoot 'System32\sc.exe'
                & $sc config WSearch start= delayed-auto | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'SetDelayedStartFailed' }
                $actions += 'DelayedStart=On'
            }
        }
    }

    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='WSearch'" -ErrorAction Stop
    $database = Get-IndexDatabase
    $dbMissing = ($null -eq $database) -or ([int64]$database.Length -eq 0)
    $indexerUp = @(Get-Process -Name 'SearchIndexer' -ErrorAction SilentlyContinue).Count -gt 0
    $rebuild = ($ForceRebuild -or $dbMissing) -and $blocked.Count -eq 0

    if ($rebuild) {
        Stop-Service -Name 'WSearch' -Force -ErrorAction Stop
        if (-not (Wait-ServiceState -ServiceName 'WSearch' -State 'Stopped' -TimeoutSeconds 60)) {
            throw 'ServiceStopTimeout'
        }
        $target = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
        $null = New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop
        foreach ($name in $IndexFileNames) {
            $source = Join-Path $IndexDirectory $name
            if (Test-Path -LiteralPath $source) {
                Move-Item -LiteralPath $source -Destination (Join-Path $target $name) -Force -ErrorAction Stop
                $actions += "Backup=$name"
            }
        }
        Start-Service -Name 'WSearch' -ErrorAction Stop
        $actions += 'IndexRebuild=Started'
        Write-IRTLog "Index database moved to $target and rebuild started"
    }
    elseif ($blocked.Count -eq 0) {
        if ($service.State -ne 'Running') {
            Start-Service -Name 'WSearch' -ErrorAction Stop
            $actions += 'Service=Started'
        }
        elseif (-not $indexerUp) {
            Restart-Service -Name 'WSearch' -Force -ErrorAction Stop
            $actions += 'Indexer=Restarted'
        }
    }

    if ($RestartSearchHost) {
        $searchHost = @(Get-Process -Name 'SearchHost', 'SearchUI' -ErrorAction SilentlyContinue)
        if ($searchHost.Count -gt 0) {
            $searchHost | Stop-Process -Force -ErrorAction SilentlyContinue
            $actions += "SearchHost=Restarted($($searchHost.Count))"
        }
    }

    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 3
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='WSearch'" -ErrorAction SilentlyContinue
        $database = Get-IndexDatabase
        $indexerUp = @(Get-Process -Name 'SearchIndexer' -ErrorAction SilentlyContinue).Count -gt 0
    } while (((Get-Date) -lt $deadline) -and ($service.State -ne 'Running' -or -not $indexerUp -or $null -eq $database))

    $remaining = @()
    if ($service.State -ne 'Running' -and $blocked.Count -eq 0) { $remaining += 'Service=Stopped' }
    if ($service.StartMode -eq 'Disabled' -and $blocked.Count -eq 0) { $remaining += 'StartType=Disabled' }
    if (-not $indexerUp) { $remaining += 'Indexer=NotRunning' }
    if ($null -eq $database) { $remaining += 'IndexDb=Missing' }

    $indexerState = 'NotRunning'
    if ($indexerUp) { $indexerState = 'Running' }
    $dbState = 'Missing'
    if ($null -ne $database) { $dbState = '{0}MB' -f [math]::Round(([int64]$database.Length / 1MB), 1) }
    $done = 'None'
    if ($actions.Count -gt 0) { $done = $actions -join ',' }

    $summary = "Service=$($service.State); StartType=$($service.StartMode); Indexer=$indexerState; IndexDb=$dbState; Rebuild=$rebuild; Actions=$done"

    if ($remaining.Count -gt 0) { Exit-Script 1 "Failed | $($remaining -join '; '); Actions=$done" }
    if ($blocked.Count -gt 0 -and $service.State -ne 'Running') { Exit-Script 1 "Blocked | $($blocked -join '; '); Service=$($service.State)" }
    if ($actions.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: Failed | Operation=Remediate; HResult=$($_.Exception.HResult)" }
