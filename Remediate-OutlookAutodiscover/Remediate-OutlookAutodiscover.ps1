<#
.SYNOPSIS
  Remediation script for the Outlook Autodiscover lookup methods in a hybrid Exchange organization.

.DESCRIPTION
  Writes the Autodiscover DWORDs that keep the client on the on-premises endpoint. Stops the root domain lookup and the Microsoft 365 direct connect lookup, and clears the exclusions on SCP and on the autodiscover domain. Exports the current key first and verifies the result. Exits 0 when the values are correct, 1 when the change could not be verified.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$OfficeVersion     = '16.0'
$EnableRemediation = $false
$ExpectedValues = [ordered]@{
    'ExcludeHttpsRootDomain'         = 1
    'ExcludeExplicitO365Endpoint'    = 1
    'ExcludeHttpsAutoDiscoverDomain' = 0
    'ExcludeScpLookup'               = 0
}

$PackageName = 'OutlookAutodiscover'
$Phase       = 'Remediate'
$LogDir      = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Logs'
$LogFile     = Join-Path $LogDir "IRT_$PackageName.log"
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-RegistryValue {
    param([string]$Path, [string]$Name)

    $props = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $props) { return $null }
    $prop = $props.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function ConvertTo-ValueNumber {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [int]) { return [int]$Value }
    if ($Value -is [long]) { return [int]$Value }
    $number = 0
    if ([int]::TryParse([string]$Value, [ref]$number)) { return $number }
    return $null
}

function Get-AutodiscoverState {
    param([string]$Version)

    $userKey    = "HKCU:\Software\Microsoft\Office\$Version\Outlook\AutoDiscover"
    $policyKeys = @(
        "HKCU:\Software\Policies\Microsoft\Office\$Version\Outlook\AutoDiscover"
        "HKLM:\SOFTWARE\Policies\Microsoft\Office\$Version\Outlook\AutoDiscover"
    )

    foreach ($name in $ExpectedValues.Keys) {
        $expected = [int]$ExpectedValues[$name]
        $raw      = Get-RegistryValue -Path $userKey -Name $name
        $current  = ConvertTo-ValueNumber -Value $raw
        $isPolicy = $false

        foreach ($policyKey in $policyKeys) {
            if (Test-Path -LiteralPath $policyKey) {
                if ($null -ne (Get-RegistryValue -Path $policyKey -Name $name)) { $isPolicy = $true }
            }
        }

        if ($isPolicy) {
            $state = 'Policy'
            $text  = 'Policy'
        }
        elseif ($null -ne $current -and $current -eq $expected) {
            $state = 'OK'
            $text  = [string]$current
        }
        elseif ($null -eq $raw) {
            $text = 'Missing'
            if ($expected -eq 0) { $state = 'OK' } else { $state = 'Drift' }
        }
        else {
            $state = 'Drift'
            $text  = 'Invalid'
            if ($null -ne $current) { $text = [string]$current }
        }

        [pscustomobject]@{ Name = $name; State = $state; Text = $text; Expected = $expected }
    }
}

function Get-BackupDirectory {
    $candidates = @(
        (Join-Path $env:ProgramData 'IntuneRemediations\Backup')
        (Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup')
    )
    foreach ($dir in $candidates) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            return $dir
        }
        catch { }
    }
    return $env:TEMP
}

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }
    if (-not (Test-Path -LiteralPath "HKCU:\Software\Microsoft\Office\$OfficeVersion\Outlook")) {
        Exit-Script 0 "NotApplicable | Office=$OfficeVersion; Outlook=NotInitialized"
    }

    $userKey = "HKCU:\Software\Microsoft\Office\$OfficeVersion\Outlook\AutoDiscover"
    $states  = @(Get-AutodiscoverState -Version $OfficeVersion)
    $all     = ($states | ForEach-Object { '{0}={1}' -f $_.Name, $_.Text }) -join '; '
    $drift   = @($states | Where-Object { $_.State -eq 'Drift' })
    $policy  = @($states | Where-Object { $_.State -eq 'Policy' })

    if ($drift.Count -eq 0) {
        if ($policy.Count -gt 0) { Exit-Script 0 "Managed | Office=$OfficeVersion; $all; Reason=ManagedByPolicy" }
        Exit-Script 0 "Healthy | Office=$OfficeVersion; $all"
    }

    $detail = ($drift | ForEach-Object { '{0}={1}' -f $_.Name, $_.Text }) -join '; '
    if (-not $EnableRemediation) { Exit-Script 1 "ReportOnly | Office=$OfficeVersion; $detail" }

    $backupFile = ''
    if (Test-Path -LiteralPath $userKey) {
        $backupDir  = Get-BackupDirectory
        $backupFile = Join-Path $backupDir ('Autodiscover_{0}_{1}.reg' -f $OfficeVersion, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $regPath    = 'HKCU\Software\Microsoft\Office\' + $OfficeVersion + '\Outlook\AutoDiscover'
        & reg.exe export "$regPath" "$backupFile" /y | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-IRTLog 'Backup export failed, continuing' 'WARN'
            $backupFile = ''
        }
        else { Write-IRTLog "Backup written to $backupFile" }
    }

    $changed = @()
    foreach ($item in $drift) {
        if (-not (Test-Path -LiteralPath $userKey)) { New-Item -Path $userKey -Force | Out-Null }
        New-ItemProperty -LiteralPath $userKey -Name $item.Name -PropertyType DWord -Value $item.Expected -Force | Out-Null
        $changed += $item.Name
        Write-IRTLog ('{0} set to {1}' -f $item.Name, $item.Expected)
    }

    $after    = @(Get-AutodiscoverState -Version $OfficeVersion)
    $left     = @($after | Where-Object { $_.State -eq 'Drift' })
    $summary  = 'Office={0}; Changed={1}' -f $OfficeVersion, ($changed -join ',')
    if ($backupFile) { $summary = $summary + '; Backup=' + (Split-Path -Path $backupFile -Leaf) }

    if ($left.Count -gt 0) {
        $remaining = ($left | ForEach-Object { '{0}={1}' -f $_.Name, $_.Text }) -join '; '
        Exit-Script 1 "Failed | $summary; Remaining=$remaining"
    }

    $sessionId = (Get-Process -Id $PID).SessionId
    $running   = (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId }).Count -gt 0)
    if ($running) { Exit-Script 0 "Fixed | $summary; Effective=NextOutlookStart" }
    Exit-Script 0 "Fixed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
