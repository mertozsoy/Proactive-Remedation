<#
.SYNOPSIS
    Intune Proactive Remediation - Detection: Winget varlik denetimi

.DESCRIPTION
    Cihazda winget (Microsoft.App Installer) kurulu ve calisir durumda olup olmadigini denetler.
    Winget kurulu ve calisiyorsa cihaz uyumlu (exit 0), kurulu degilse veya calismiyorsa
    uyumsuz (exit 1) sayilir. Boylece winget olmayan cihazlar tespit edilir.
    Log: C:\Temp\IntunePR-WinGetVarlik-Detection.log

.NOTES
    Run as: System
    Context: 64 Bit
#>

$LogPath = "C:\Temp\IntunePR-WinGetVarlik-Detection.log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Output $line
    try {
        $dir = Split-Path $LogPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }
    catch {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] LOG HATASI (dosyaya yazilamadi): $($_.Exception.Message)"
    }
}

function Resolve-Winget {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $userWinget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (Test-Path $userWinget) { return $userWinget }
    $sysWinget = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($sysWinget) { return $sysWinget.FullName }
    $appx = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction SilentlyContinue
    if ($appx) {
        $appxWinget = Join-Path $appx.InstallLocation "winget.exe"
        if (Test-Path $appxWinget) { return $appxWinget }
    }
    return $null
}

try {
    Write-Log "Detection baslatildi - winget varlik kontrolu..."

    $winget = Resolve-Winget
    if (-not $winget) {
        Write-Log "UYUMSUZ: winget bulunamadi (kurulu degil veya erisilemiyor)."
        exit 1
    }
    Write-Log "winget yolu: $winget"

    $ver = & $winget --version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Log "UYUMSUZ: winget bulundu ancak calistirilamiyor. Cikti: $($ver.Trim())"
        exit 1
    }
    Write-Log "winget surumu: $($ver.Trim())"

    Write-Log "UYUMLU: winget kurulu ve calisir durumda."
    exit 0
}
catch {
    Write-Log "UYUMSUZ: HATA - $($_.Exception.Message)"
    exit 1
}
