<#
.SYNOPSIS
  Detection script for the Outlook Autodiscover lookup methods in a hybrid Exchange organization.

.DESCRIPTION
  Reads the Autodiscover DWORDs of the signed-in user under HKCU\Software\Microsoft\Office\<version>\Outlook\AutoDiscover and compares them with the expected map. Skips any value that is also set under a policy hive. Exits 1 if a lookup method that leads to the root domain or to the Microsoft 365 endpoint is still enabled, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$OfficeVersion = '16.0'
$ExpectedValues = [ordered]@{
    'ExcludeHttpsRootDomain'         = 1
    'ExcludeExplicitO365Endpoint'    = 1
    'ExcludeHttpsAutoDiscoverDomain' = 0
    'ExcludeScpLookup'               = 0
}

$PackageName = 'OutlookAutodiscover'
$Phase       = 'Detect'
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

try {
    $ErrorActionPreference = 'Stop'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }
    if (-not (Test-Path -LiteralPath "HKCU:\Software\Microsoft\Office\$OfficeVersion\Outlook")) {
        Exit-Script 0 "NotApplicable | Office=$OfficeVersion; Outlook=NotInitialized"
    }

    $states = @(Get-AutodiscoverState -Version $OfficeVersion)
    foreach ($state in $states) { Write-IRTLog ('{0}={1} ({2})' -f $state.Name, $state.Text, $state.State) }

    $all    = ($states | ForEach-Object { '{0}={1}' -f $_.Name, $_.Text }) -join '; '
    $drift  = @($states | Where-Object { $_.State -eq 'Drift' })
    $policy = @($states | Where-Object { $_.State -eq 'Policy' })

    if ($drift.Count -gt 0) {
        $detail = ($drift | ForEach-Object { '{0}={1}' -f $_.Name, $_.Text }) -join '; '
        Exit-Script 1 "Drift | Office=$OfficeVersion; $detail"
    }
    if ($policy.Count -gt 0) { Exit-Script 0 "Managed | Office=$OfficeVersion; $all; Reason=ManagedByPolicy" }
    Exit-Script 0 "Healthy | Office=$OfficeVersion; $all"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
