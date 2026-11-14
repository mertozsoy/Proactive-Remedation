<#
.SYNOPSIS
  Detection script for a wrong architecture WebView2 Runtime on Windows on ARM devices.

.DESCRIPTION
  On ARM64 devices reads the per-machine WebView2 Runtime version from the Edge Update client keys and checks the PE machine type of msedgewebview2.exe. Exits 1 if the runtime binary is not ARM64 or the registered version has no binary, 0 otherwise. Non ARM64 devices and devices without a per-machine runtime return NotApplicable.

.NOTES
  Author: Mert Ozsoy
  Version: 1.1
  Run As: System
#>
$WebView2ClientKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
)
$WebView2AppRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application'

$PackageName = 'WebView2Arm64'
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

    $state = Get-WebView2State
    if ($state.Version -eq 'None') { Exit-Script 0 'NotApplicable | WebView2=NotInstalledPerMachine' }

    Write-IRTLog "WebView2 $($state.Version) binary architecture $($state.Arch)"
    if ($state.Arch -eq 'ARM64') { Exit-Script 0 "Healthy | Version=$($state.Version); Arch=ARM64" }
    Exit-Script 1 "Drift | Version=$($state.Version); Arch=$($state.Arch); Expected=ARM64"
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
