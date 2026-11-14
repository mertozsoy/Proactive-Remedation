<#
.SYNOPSIS
  Remediation script for legacy TLS 1.0 and TLS 1.1 settings.

.DESCRIPTION
  Disables TLS 1.0 and TLS 1.1 in SCHANNEL and sets the .NET Framework strong crypto values, then checks the result. Exits 0 when all values are set; a restart is needed for SCHANNEL changes.

.NOTES
  Author: Mert Ozsoy
  Version: 1.0
  Run As: System
#>
$Protocols         = @('TLS 1.0', 'TLS 1.1')
$IncludeServerSide = $true
$DotNetVersions    = @('v4.0.30319', 'v2.0.50727')

$PackageName = 'LegacyTls'
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

function Set-DwordValue { param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    $current = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($current -ne $Value) {
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-IRTLog "$Path\$Name : $current -> $Value"
    }
}

try {
    $schannel = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
    $sides    = @('Client')
    if ($IncludeServerSide) { $sides += 'Server' }
    $targets  = New-Object System.Collections.Generic.List[object]

    foreach ($protocol in $Protocols) {
        foreach ($side in $sides) {
            $key = Join-Path $schannel "$protocol\$side"
            Set-DwordValue -Path $key -Name 'Enabled' -Value 0
            Set-DwordValue -Path $key -Name 'DisabledByDefault' -Value 1
            $targets.Add(@{ Path = $key; Values = @{ Enabled = 0; DisabledByDefault = 1 } })
        }
    }

    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\.NETFramework', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework')) {
        foreach ($version in $DotNetVersions) {
            $key = Join-Path $root $version
            if (-not (Test-Path -LiteralPath $key)) { continue }
            Set-DwordValue -Path $key -Name 'SchUseStrongCrypto' -Value 1
            Set-DwordValue -Path $key -Name 'SystemDefaultTlsVersions' -Value 1
            $targets.Add(@{ Path = $key; Values = @{ SchUseStrongCrypto = 1; SystemDefaultTlsVersions = 1 } })
        }
    }

    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($target in $targets) {
        $props = Get-ItemProperty -LiteralPath $target.Path -ErrorAction SilentlyContinue
        foreach ($name in $target.Values.Keys) {
            if ($null -eq $props -or $props.$name -ne $target.Values[$name]) { $failed.Add("$($target.Path)\$name") }
        }
    }

    if ($failed.Count -gt 0) { Exit-Script 1 "Failed | NotSet=$($failed -join ',')" }
    Exit-Script 0 ('Remediated | Protocols={0}; Sides={1}; Keys={2}; RestartRequired=Yes' -f ($Protocols -join ','), ($sides -join '+'), $targets.Count)
}
catch { Exit-Script 1 "Error: $($_.Exception.Message)" }
