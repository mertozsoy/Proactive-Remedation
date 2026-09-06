<#
.SYNOPSIS
    Intune Proactive Remediation - Remediation: Winget (App Installer) kurulumu

.DESCRIPTION
    Cihazda winget yoksa veya calismiyorsa kurulumunu yapar.
    1) Mevcut ama bozuk paket varsa yeniden kayit (re-register) dener
    2) Paket yoksa aka.ms/getwinget uzerinden App Installer MSIX bundle indirip kurar
    3) Kurulum sonrasi winget --version ile dogrulama yapar
    Log: C:\Temp\IntunePR-WinGetKur-Remediation.log

.NOTES
    Run as: System
    Context: 64 Bit
#>

$LogPath = "C:\Temp\IntunePR-WinGetKur-Remediation.log"
$BundlePath = "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"

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
    return $null
}

function Test-WingetWorks {
    $winget = Resolve-Winget
    if (-not $winget) { return $false }
    $null = & $winget --version 2>&1
    return ($LASTEXITCODE -eq 0)
}

try {
    Write-Log "Remediation baslatildi - winget kurulumu..."

    if (Test-WingetWorks) {
        Write-Log "Bilgi: winget zaten kurulu ve calisiyor. Islem gerekmiyor."
        exit 0
    }

    # 1) Paket var ama calismiyor olabilir: yeniden kayit dene
    $appx = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction SilentlyContinue
    if ($appx) {
        Write-Log "Paket mevcut ancak calismiyor. Yeniden kayit deneniyor: $($appx.InstallLocation)"
        try {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($appx.InstallLocation)\AppXManifest.xml" -ErrorAction Stop
            Write-Log "Yeniden kayit tamamlandi."
        }
        catch {
            Write-Log "Yeniden kayit basarisiz: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Paket kurulu degil. Yeni kurulum yapilacak."
    }

    if (Test-WingetWorks) {
        $ver = & (Resolve-Winget) --version 2>&1 | Out-String
        Write-Log "BASARILI: winget kullanima hazir. Surum: $($ver.Trim())"
        exit 0
    }

    # 2) Paket yoksa MSIX bundle indir ve kur
    Write-Log "Bundle indiriliyor: https://aka.ms/getwinget"
    try {
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile $BundlePath -UseBasicParsing -ErrorAction Stop
        Write-Log "Bundle indirildi: $BundlePath ($((Get-Item $BundlePath).Length) byte)"
    }
    catch {
        Write-Log "HATA: Bundle indirilemedi: $($_.Exception.Message)"
        exit 1
    }

    try {
        Add-AppxPackage -Path $BundlePath -ForceUpdateFromAnyVersion -ErrorAction Stop
        Write-Log "Bundle kurulumu tamamlandi."
    }
    catch {
        Write-Log "HATA: Bundle kurulamadi: $($_.Exception.Message)"
        Write-Log "Not: Magaza kapaliysa veya bagimliliklar (VCLibs vb.) eksikse kurulum basarisiz olur. Microsoft Store uzerinden 9NBLPGH4N681 (App Installer) acilmasini da deneyin."
        exit 1
    }

    # 3) Dogrula
    if (Test-WingetWorks) {
        $ver = & (Resolve-Winget) --version 2>&1 | Out-String
        Write-Log "BASARILI: winget kuruldu ve calisiyor. Surum: $($ver.Trim())"
        exit 0
    }

    Write-Log "BASARISIZ: Kurulum yapildi ancak winget dogrulanamadi. Bir sonraki dongude tekrar denenecek."
    exit 1
}
catch {
    Write-Log "HATA: $($_.Exception.Message)"
    exit 1
}
