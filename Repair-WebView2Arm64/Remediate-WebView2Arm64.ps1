<#
.SYNOPSIS
  Remediation script that reinstalls the ARM64 WebView2 Runtime on Windows on ARM devices.

.DESCRIPTION
  Runs the ARM64 Evergreen Standalone Installer from $InstallerPath with /silent /install and checks the PE machine type of msedgewebview2.exe again. With an empty $InstallerPath it only reports. Exits 0 if the runtime binary is ARM64 afterwards, 1 otherwise.

.NOTES
  Author: Mert Ozsoy
  Version: 1.1
  Run As: System
#>
$InstallerPath     = ''
$InstallTimeoutSec = 900
$WebView2ClientKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
)
$WebView2AppRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application'

$PackageName = 'WebView2Arm64'
$Phase       = 'Remediate'
$LogFile     = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\IRT_$PackageName.log"
function Write-IRTLog { param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Phase, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Exit-Script { param([int]$Code, [string]$Summary)
    if ($Summary.Length -gt 2000) { $Summary = $Summary.Substring(0, 1997) + '...' }
    Write-IRTLog "EXIT $Code | $Summary"; Write-Output $Summary; exit $Code
}

function Get-PeMachine { param([string]$Path)
    $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 4
        $machine = $reader.ReadUInt16()
    }
    finally { $stream.Close() }
    switch ($machine) { 0xAA64 { 'ARM64' } 0x8664 { 'x64' } 0x014C { 'x86' } default { '0x{0:X4}' -f $machine } }
}

function Get-WebView2State {
    $versions = @()
    foreach ($key in $WebView2ClientKeys) {
        $value = (Get-ItemProperty -LiteralPath $key -Name pv -ErrorAction SilentlyContinue).pv
        if ($value -and $value -ne '0.0.0.0' -and $versions -notcontains $value) { $versions += $value }
    }
    if ($versions.Count -eq 0) { return [pscustomobject]@{ Version = 'None'; Arch = 'Missing' } }
    foreach ($version in $versions) {
        $exe = Join-Path $WebView2AppRoot "$version\msedgewebview2.exe"
        if (Test-Path -LiteralPath $exe) {
            return [pscustomobject]@{ Version = $version; Arch = (Get-PeMachine -Path $exe) }
        }
    }
    [pscustomobject]@{ Version = $versions[0]; Arch = 'Missing' }
}

try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
    if ($cpu.Architecture -ne 12) { Exit-Script 0 "NotApplicable | CpuArchitecture=$($cpu.Architecture)" }

    $before = Get-WebView2State
    if ($before.Arch -eq 'ARM64') { Exit-Script 0 "Healthy | Version=$($before.Version); Arch=ARM64" }
    if (-not $InstallerPath) { Exit-Script 1 "ReportOnly | Version=$($before.Version); Arch=$($before.Arch); InstallerPath=NotSet" }
    if (-not (Test-Path -LiteralPath $InstallerPath)) { Exit-Script 1 "Failed | InstallerPath=NotFound; Arch=$($before.Arch)" }

    $process = Start-Process -FilePath $InstallerPath -ArgumentList '/silent', '/install' -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit($InstallTimeoutSec * 1000)) { Exit-Script 1 "Failed | Installer=Timeout; Arch=$($before.Arch)" }
    Write-IRTLog "Installer exit code $($process.ExitCode)"

    $after = Get-WebView2State
    $summary = 'Version={0}; Arch={1}; Before={2}; InstallerExit={3}' -f $after.Version, $after.Arch, $before.Arch, $process.ExitCode
    if ($after.Arch -eq 'ARM64') { Exit-Script 0 "Fixed | $summary" }
    Exit-Script 1 "Failed | $summary"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
