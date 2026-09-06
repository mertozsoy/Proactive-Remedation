<#
.SYNOPSIS
    Intune Proactive Remediation - Detection: Oracle Java Runtime Environment guncelleme denetimi

.DESCRIPTION
    Guncelleme mevcutsa winget ile gunceller. Guncellenmemis surum varsa guncellemeyi yapar,
    guncel ise uyumlu sayar. Log: C:\Temp\IntunePR-Java-Detection.log
#>

$AppId = "Oracle.JavaRuntimeEnvironment"
$LogPath = "C:\Temp\IntunePR-Java-Detection.log"

function Write-Log {
    param([string]$Message)
    $line = $Message
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
    return $null
}

function Get-InstalledJavaVersion {
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $found = $null
    foreach ($path in $uninstallPaths) {
        $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match "Java 8 Update" -and $_.DisplayVersion }
        foreach ($item in $items) {
            $ver = $null
            if ([version]::TryParse($item.DisplayVersion, [ref]$ver)) {
                if (-not $found -or $ver -gt $found) { $found = $ver }
            }
        }
    }
    return $found
}

try {
    Write-Log "Detection baslatildi - Oracle.JavaRuntimeEnvironment kontrolu..."

    $installed = Get-InstalledJavaVersion
    if (-not $installed) {
        Write-Log "Bilgi: 'Java 8 Update' kurulu degil. Kurulum disinda kaldigi icin uyumlu sayilir."
        exit 0
    }
    Write-Log "Kurulu surum: $installed"

    $winget = Resolve-Winget
    if (-not $winget) {
        Write-Log "HATA: winget bulunamadi."
        exit 1
    }
    Write-Log "winget yolu: $winget"

    $show = & $winget show --id $AppId --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    $showExit = $LASTEXITCODE
    Write-Log "winget show cikis kodu: $showExit"

    $match = [regex]::Match($show, '(?im)^\s*Version:\s*([\d\.]+)')
    if (-not $match.Success) {
        Write-Log "HATA: winget show ciktisindan mevcut surum alinamadi. Cikti:"
        Write-Log $show.Trim()
        exit 1
    }
    $available = [version]$match.Groups[1].Value
    Write-Log "Mevcut (winget) surum: $available"

    if ($installed -ge $available) {
        Write-Log "UYUMLU: Java Runtime guncel (kurulu: $installed)."
        exit 0
    }

    Write-Log "GUNCELLEME MEVCUT (kurulu: $installed -> mevcut: $available). Upgrade baslatiliyor..."

    $javaProcesses = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match "^(java|javaw|javaws|jusched|jucheck)$" }
    if ($javaProcesses) {
        foreach ($p in $javaProcesses) { Write-Log "Java sureci kapatiliyor: $($p.ProcessName) (PID: $($p.Id))" }
        Stop-Process -Id $javaProcesses.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    else {
        Write-Log "Calisan Java sureci bulunamadi."
    }

    $up = & $winget upgrade --id $AppId --accept-source-agreements --accept-package-agreements --disable-interactivity --silent 2>&1 | Out-String
    $upExit = $LASTEXITCODE
    Write-Log "winget upgrade cikis kodu: $upExit"
    Write-Log "winget upgrade ciktisi:"
    Write-Log $up.Trim()

    Start-Sleep -Seconds 5

    $new = Get-InstalledJavaVersion
    if ($new -and $new -ge $available) {
        Write-Log "BASARILI: Java guncellendi. Yeni kurulu surum: $new"
        exit 0
    }
    else {
        Write-Log "BASARISIZ: Java hala guncel degil (kurulu: $new). Bir sonraki dongude tekrar denenecek."
        exit 1
    }
}
catch {
    Write-Log "HATA: $($_.Exception.Message)"
    exit 1
}
