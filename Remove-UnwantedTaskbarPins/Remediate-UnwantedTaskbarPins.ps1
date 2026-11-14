<#
.SYNOPSIS
  Remediation script that removes unwanted user taskbar pins.

.DESCRIPTION
  Invokes the localized unpin verb exposed by Microsoft Store and Copilot AppsFolder items.
  Rechecks fresh shell verbs before reporting success. Exits 0 on success, 1 on failure.
  Does not modify layout policies, uninstall apps or restart Explorer.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: User
#>
$UnwantedApps = @('Microsoft Store', 'Copilot')
$TaskbarPinsManagedByPolicy = $false
$VerificationAttempts = 10
$VerificationDelaySeconds = 1
$UnpinVerbNames = @(
    'Unpin from taskbar'
    'G\u00f6rev \u00e7ubu\u011fundan kald\u0131r'
    'Von Taskleiste l\u00f6sen'
    'Von der Taskleiste l\u00f6sen'
    'D\u00e9tacher de la barre des t\u00e2ches'
    'Desanclar de la barra de tareas'
)
$PinVerbNames = @(
    'Pin to taskbar'
    'G\u00f6rev \u00e7ubu\u011funa sabitle'
    'An Taskleiste anheften'
    'An die Taskleiste anheften'
    '\u00c9pingler \u00e0 la barre des t\u00e2ches'
    'Anclar a la barra de tareas'
)

$PackageName = 'UnwantedTaskbarPins'
$Phase = 'Remediate'
$LogFile = Join-Path $env:LOCALAPPDATA "IntuneRemediations\Logs\IRT_$PackageName.log"
$ErrorActionPreference = 'Stop'

function Write-IRTLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $directory = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
    catch { }
}

function Exit-Script {
    param([int]$Code, [string]$Summary)
    $Summary = $Summary -replace '[\r\n]+', ' '
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"
    Write-Output $Summary
    exit $Code
}

function ConvertTo-VerbLabel {
    param([string]$Text)
    return ([regex]::Unescape($Text).Replace('&', '').Trim()).ToLowerInvariant()
}

function Get-TargetPinState {
    param($Shell)
    $folder = $Shell.NameSpace('shell:AppsFolder')
    if ($null -eq $folder) { throw 'AppsFolderUnavailable' }
    $items = @($folder.Items())
    foreach ($app in $UnwantedApps) {
        $packageIdentity = switch ($app) {
            'Microsoft Store' { 'Microsoft.WindowsStore' }
            'Copilot' { 'Microsoft.Copilot' }
            default { throw 'UnsupportedTarget' }
        }
        $packages = @(Get-AppxPackage -Name $packageIdentity -ErrorAction Stop)
        if ($packages.Count -eq 0) {
            [pscustomobject]@{ App = $app; State = 'NotInstalled'; Verb = $null }
            continue
        }
        $families = @($packages | Select-Object -ExpandProperty PackageFamilyName -Unique)
        $targets = @($items | Where-Object { ([string]$_.Path -split '!', 2)[0] -in $families })
        if ($targets.Count -eq 0) {
            [pscustomobject]@{ App = $app; State = 'ShellItemMissing'; Verb = $null }
            continue
        }
        foreach ($item in $targets) {
            $verbs = @($item.Verbs())
            $unpin = @($verbs | Where-Object { (ConvertTo-VerbLabel -Text ([string]$_.Name)) -in $script:UnpinLabels })
            $pin = @($verbs | Where-Object { (ConvertTo-VerbLabel -Text ([string]$_.Name)) -in $script:PinLabels })
            $state = 'VerbUnavailable'
            $verb = $null
            if ($unpin.Count -eq 1 -and $pin.Count -eq 0) { $state = 'Pinned'; $verb = $unpin[0] }
            elseif ($pin.Count -eq 1 -and $unpin.Count -eq 0) { $state = 'Unpinned' }
            [pscustomobject]@{ App = $app; State = $state; Verb = $verb }
        }
    }
}

try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.IsSystem -or [System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        Exit-Script 0 'NotApplicable | Reason=InteractiveUserRequired'
    }
    if ($TaskbarPinsManagedByPolicy) { Exit-Script 0 'NotApplicable | Reason=PolicyManagedPins' }
    $script:UnpinLabels = @($UnpinVerbNames | ForEach-Object { ConvertTo-VerbLabel -Text $_ })
    $script:PinLabels = @($PinVerbNames | ForEach-Object { ConvertTo-VerbLabel -Text $_ })
    $shell = New-Object -ComObject Shell.Application
    $states = @(Get-TargetPinState -Shell $shell)
    $summary = ($states | ForEach-Object { '{0}={1}' -f $_.App, $_.State }) -join '; '
    if (@($states | Where-Object { $_.State -notin @('Pinned', 'Unpinned', 'NotInstalled') }).Count -gt 0) {
        Exit-Script 1 "Failed | $summary"
    }
    $pinned = @($states | Where-Object { $_.State -eq 'Pinned' })
    if ($pinned.Count -eq 0) { Exit-Script 0 "Healthy | $summary" }
    foreach ($target in $pinned) {
        Write-IRTLog ('Unpin requested | App={0}' -f $target.App)
        $target.Verb.DoIt() | Out-Null
    }
    for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
        Start-Sleep -Seconds $VerificationDelaySeconds
        $states = @(Get-TargetPinState -Shell $shell)
        $remaining = @($states | Where-Object { $_.State -notin @('Unpinned', 'NotInstalled') })
        $summary = ($states | ForEach-Object { '{0}={1}' -f $_.App, $_.State }) -join '; '
        if ($remaining.Count -eq 0) { Exit-Script 0 "Fixed | $summary" }
    }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 ('Failed | Reason=ShellError; HResult={0}' -f $_.Exception.HResult) }
