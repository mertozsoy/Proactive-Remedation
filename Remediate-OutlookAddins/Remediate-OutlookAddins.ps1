<#
.SYNOPSIS
  Remediation script for business-critical Outlook COM add-ins.

.DESCRIPTION
  Turns the configured add-ins back on, removes their entries from the disabled items list and adds them to the do-not-disable allow list so Outlook stops turning them off. Backs up the resiliency and add-in keys first and verifies the result. Exits 0 when the add-ins are protected, 1 when the change could not be verified.

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
$EnableRemediation = $true
$SetAllowList = $true
$ClearDisabledItems = $true
$ResetLoadBehavior = $true
$ProtectionValue = 1
$KeepBackupDays = 30

$PackageName = 'OutlookAddins'
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

function Export-KeyBackup { param([string]$ProviderPath, [string]$BackupRoot, [string]$Label)
    if (-not (Test-Path -LiteralPath $ProviderPath)) { return }
    $file = Join-Path $BackupRoot ('{0}_{1}.reg' -f $Label, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $regPath = $ProviderPath -replace '^HKCU:', 'HKCU' -replace '^HKLM:', 'HKLM'
    & reg.exe export "$regPath" "$file" /y | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-IRTLog "Backup export failed for $regPath" 'WARN' }
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

    $before = @()
    foreach ($addin in $CriticalAddins) { $before += Get-AddinState -ProgId $addin.ProgId }
    $installed = @($before | Where-Object { $_.State -ne 'NotInstalled' })
    if ($installed.Count -eq 0) { Exit-Script 0 'NotApplicable | CriticalAddins=NotInstalled' }
    $drift = @($before | Where-Object { $_.State -in 'DisabledItems', 'LoadBehavior0', 'LoadBehavior2', 'NotProtected' })
    $summary = (@($before | ForEach-Object { '{0}={1}' -f $_.ProgId, $_.State }) -join '; ')
    if ($drift.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    if (-not $EnableRemediation) { Exit-Script 0 "ReportOnly | $summary" }

    $backupRoot = Join-Path $env:LOCALAPPDATA 'IntuneRemediations\Backup'
    if (-not (Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
    Get-ChildItem -LiteralPath $backupRoot -Filter 'OutlookAddins_*.reg' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepBackupDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Export-KeyBackup -ProviderPath $ResiliencyKey -BackupRoot $backupRoot -Label 'OutlookAddins_Resiliency'
    foreach ($addin in $drift) {
        $parent = Split-Path -Path $addin.KeyPath -Parent
        Export-KeyBackup -ProviderPath $parent -BackupRoot $backupRoot -Label ('OutlookAddins_' + $addin.ProgId)
    }

    $failed = @()
    foreach ($addin in $drift) {
        try {
            if ($SetAllowList) {
                if (-not (Test-Path -LiteralPath $ResiliencyKey)) { New-Item -Path $ResiliencyKey -Force | Out-Null }
                if (-not (Test-Path -LiteralPath $AllowListKey)) { New-Item -Path $AllowListKey -Force | Out-Null }
                New-ItemProperty -LiteralPath $AllowListKey -Name $addin.ProgId -PropertyType DWord -Value $ProtectionValue -Force | Out-Null
                Write-IRTLog "Allow list entry written for $($addin.ProgId)"
            }
            if ($ClearDisabledItems -and $addin.Disabled -gt 0) {
                foreach ($name in @(Get-DisabledItemNames -ProgId $addin.ProgId)) {
                    Remove-ItemProperty -LiteralPath $DisabledItemsKey -Name $name -Force -ErrorAction Stop
                    Write-IRTLog "Disabled item removed for $($addin.ProgId): $name"
                }
            }
            if ($ResetLoadBehavior -and $null -ne $addin.LoadBehavior -and [int]$addin.LoadBehavior -ne 3) {
                Set-ItemProperty -LiteralPath $addin.KeyPath -Name 'LoadBehavior' -Value 3 -Type DWord -ErrorAction Stop
                Write-IRTLog "LoadBehavior set to 3 for $($addin.ProgId)"
            }
        }
        catch {
            Write-IRTLog "Fix failed for $($addin.ProgId): $($_.Exception.Message)" 'ERROR'
            $failed += $addin.ProgId
        }
    }

    $after = @()
    foreach ($addin in $CriticalAddins) { $after += Get-AddinState -ProgId $addin.ProgId }
    $result = (@($after | ForEach-Object { '{0}={1}' -f $_.ProgId, $_.State }) -join '; ')
    $remaining = @($after | Where-Object { $_.State -in 'DisabledItems', 'LoadBehavior0', 'LoadBehavior2', 'NotProtected' })
    if ($remaining.Count -gt 0) {
        Exit-Script 1 "Failed | $result; FailedFixes=$(@($failed).Count)"
    }
    $sessionId = (Get-Process -Id $PID).SessionId
    $running = (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId }).Count -gt 0)
    if ($running) { Exit-Script 0 "Fixed | $result; Effective=NextOutlookStart" }
    Exit-Script 0 "Fixed | $result"
}
catch { Exit-Script 1 ('Error: Failed | Operation=Remediate; HResult={0}' -f $_.Exception.HResult) }
