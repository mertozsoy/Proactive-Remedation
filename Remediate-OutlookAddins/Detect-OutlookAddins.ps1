<#
.SYNOPSIS
  Detection script for business-critical Outlook COM add-ins.

.DESCRIPTION
  Reads the per-user load behavior and the resiliency records of the configured add-ins. Exits 1 if a critical add-in is turned off, listed as a disabled item or missing from the do-not-disable allow list, 0 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$OfficeVersion = '16.0'
$CriticalAddins = @(
    @{ ProgId = 'TeamsAddin.FastConnect' }
)
$AddinRoots = @(
    "HKCU:\Software\Microsoft\Office\$OfficeVersion\Outlook\Addins"
    'HKCU:\Software\Microsoft\Office\Outlook\Addins'
    "HKLM:\SOFTWARE\Microsoft\Office\$OfficeVersion\Outlook\Addins"
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\$OfficeVersion\Outlook\Addins"
)
$ResiliencyKey = "HKCU:\Software\Microsoft\Office\$OfficeVersion\Outlook\Resiliency"
$DisabledItemsKey = Join-Path $ResiliencyKey 'DisabledItems'
$AllowListKey = Join-Path $ResiliencyKey 'DoNotDisableAddinList'
$PolicyAddinListKey = "HKCU:\Software\Policies\Microsoft\Office\$OfficeVersion\Outlook\Resiliency\AddinList"

$PackageName = 'OutlookAddins'
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

function Get-AddinKeyPath { param([string]$ProgId)
    foreach ($root in $AddinRoots) {
        $candidate = Join-Path $root $ProgId
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ''
}

function Get-PolicyState { param([string]$ProgId)
    if (-not (Test-Path -LiteralPath $PolicyAddinListKey)) { return 'NotManaged' }
    $value = (Get-ItemProperty -LiteralPath $PolicyAddinListKey -Name $ProgId -ErrorAction SilentlyContinue).$ProgId
    if ($null -eq $value) { return 'NotManaged' }
    switch ([int]$value) {
        0 { return 'Blocked' }
        1 { return 'AlwaysEnabled' }
        default { return 'Configurable' }
    }
}

function Get-DisabledItemNames { param([string]$ProgId)
    $names = @()
    if (-not (Test-Path -LiteralPath $DisabledItemsKey)) { return $names }
    $values = (Get-ItemProperty -LiteralPath $DisabledItemsKey -ErrorAction SilentlyContinue).PSObject.Properties |
        Where-Object { $_.Name -notlike 'PS*' }
    foreach ($value in $values) {
        $hit = $false
        if ($value.Value -is [byte[]]) {
            $wide = [System.Text.Encoding]::Unicode.GetString($value.Value)
            $narrow = [System.Text.Encoding]::ASCII.GetString($value.Value)
            if ($wide.IndexOf($ProgId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            if ($narrow.IndexOf($ProgId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
        }
        elseif ($null -ne $value.Value) {
            if ([string]$value.Value -match [regex]::Escape($ProgId)) { $hit = $true }
        }
        if ($hit) { $names += $value.Name }
    }
    return $names
}

function Get-AddinState { param([string]$ProgId)
    $state = [pscustomobject]@{
        ProgId       = $ProgId
        KeyPath      = ''
        LoadBehavior = $null
        Disabled     = 0
        Protected    = $false
        Policy       = 'NotManaged'
        State        = 'Unknown'
    }
    $state.Policy = Get-PolicyState -ProgId $ProgId
    $state.KeyPath = Get-AddinKeyPath -ProgId $ProgId
    if ($state.Policy -eq 'Blocked') { $state.State = 'ManagedBlocked'; return $state }
    if (-not $state.KeyPath) { $state.State = 'NotInstalled'; return $state }

    $state.LoadBehavior = (Get-ItemProperty -LiteralPath $state.KeyPath -Name 'LoadBehavior' -ErrorAction SilentlyContinue).LoadBehavior
    $state.Disabled = @(Get-DisabledItemNames -ProgId $ProgId).Count
    if (Test-Path -LiteralPath $AllowListKey) {
        $allow = (Get-ItemProperty -LiteralPath $AllowListKey -Name $ProgId -ErrorAction SilentlyContinue).$ProgId
        if ($null -ne $allow) { $state.Protected = $true }
    }

    if ($state.Disabled -gt 0) { $state.State = 'DisabledItems' }
    elseif ($null -ne $state.LoadBehavior -and [int]$state.LoadBehavior -ne 3) { $state.State = 'LoadBehavior' + [int]$state.LoadBehavior }
    elseif (-not $state.Protected) { $state.State = 'NotProtected' }
    else { $state.State = 'OK' }
    return $state
}

try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
        Exit-Script 0 'NotApplicable | Context=ServiceAccount; Required=User'
    }
    if (-not $CriticalAddins -or $CriticalAddins.Count -eq 0) { Exit-Script 0 'NotApplicable | CriticalAddins=Empty' }
    if (-not (Test-Path -LiteralPath "HKCU:\Software\Microsoft\Office\$OfficeVersion")) {
        Exit-Script 0 'NotApplicable | Office=NotInitialized'
    }

    $states = @()
    foreach ($addin in $CriticalAddins) { $states += Get-AddinState -ProgId $addin.ProgId }

    $installed = @($states | Where-Object { $_.State -ne 'NotInstalled' })
    if ($installed.Count -eq 0) { Exit-Script 0 'NotApplicable | CriticalAddins=NotInstalled' }

    $summary = (@($states | ForEach-Object { '{0}={1}' -f $_.ProgId, $_.State }) -join '; ')
    $bad = @($states | Where-Object { $_.State -in 'DisabledItems', 'LoadBehavior0', 'LoadBehavior2', 'NotProtected' })
    if ($bad.Count -gt 0) { Exit-Script 1 "Drift | $summary" }
    Exit-Script 0 "Healthy | $summary"
}
catch { Exit-Script 1 ('Error: Failed | Operation=Detect; HResult={0}' -f $_.Exception.HResult) }
