$logDir = "C:\Temp"
$logFile = "$logDir\WinUpdate_Remediation.log"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Host $Message
}

Write-Log "=== Windows Update Remediation Basladi ==="

# --- Registry duzeltmeleri ---
Write-Log "Adim 1/10 - Windows Update politikalari temizleniyor..."

$Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (Test-Path $Path) {
    Remove-Item -Path $Path -Recurse -Verbose
    Write-Log "  Silindi: $Path"
} else {
    Write-Log "  Yok: $Path"
}

$key = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings"
if (Test-Path $key) {
    $val = Get-Item $key -EA Ignore
    $props = $val.Property

    if ($props -contains "PausedQualityDate") {
        Remove-ItemProperty -Path $key -Name "PausedQualityDate" -Verbose -ErrorAction SilentlyContinue
        Write-Log "  Temizlendi: PausedQualityDate"
    }
    if ($props -contains "PausedFeatureDate") {
        Remove-ItemProperty -Path $key -Name "PausedFeatureDate" -Verbose -ErrorAction SilentlyContinue
        Write-Log "  Temizlendi: PausedFeatureDate"
    }
    if ($props -contains "PausedQualityStatus") {
        $v = $val.GetValue("PausedQualityStatus")
        if ($v -ne "0") {
            Set-ItemProperty -Path $key -Name "PausedQualityStatus" -Value "0" -Verbose
            Write-Log "  Sifirlandi: PausedQualityStatus (eski: $v)"
        } else { Write-Log "  Zaten 0: PausedQualityStatus" }
    }
    if ($props -contains "PausedFeatureStatus") {
        $v = $val.GetValue("PausedFeatureStatus")
        if ($v -ne "0") {
            Set-ItemProperty -Path $key -Name "PausedFeatureStatus" -Value "0" -Verbose
            Write-Log "  Sifirlandi: PausedFeatureStatus (eski: $v)"
        } else { Write-Log "  Zaten 0: PausedFeatureStatus" }
    }
} else {
    Write-Log "  Yok: $key"
}

$key2 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update"
if (Test-Path $key2) {
    $val2 = Get-Item $key2 -EA Ignore
    $props2 = $val2.Property

    if ($props2 -contains "PauseQualityUpdatesStartTime") {
        Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime" -Verbose -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime_ProviderSet" -Verbose -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime_WinningProvider" -Verbose -ErrorAction SilentlyContinue
        Write-Log "  Temizlendi: PauseQualityUpdatesStartTime"
    }
    if ($props2 -contains "PauseFeatureUpdatesStartTime") {
        Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime" -Verbose -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime_ProviderSet" -Verbose -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime_WinningProvider" -Verbose -ErrorAction SilentlyContinue
        Write-Log "  Temizlendi: PauseFeatureUpdatesStartTime"
    }
    if ($props2 -contains "PauseQualityUpdates") {
        $v = $val2.GetValue("PauseQualityUpdates")
        if ($v -ne "0") {
            Set-ItemProperty -Path $key2 -Name "PauseQualityUpdates" -Value "0" -Verbose
            Write-Log "  Sifirlandi: PauseQualityUpdates (eski: $v)"
        } else { Write-Log "  Zaten 0: PauseQualityUpdates" }
    }
    if ($props2 -contains "PauseFeatureUpdates") {
        $v = $val2.GetValue("PauseFeatureUpdates")
        if ($v -ne "0") {
            Set-ItemProperty -Path $key2 -Name "PauseFeatureUpdates" -Value "0" -Verbose
            Write-Log "  Sifirlandi: PauseFeatureUpdates (eski: $v)"
        } else { Write-Log "  Zaten 0: PauseFeatureUpdates" }
    }
    if ($props2 -contains "DeferFeatureUpdatesPeriodInDays") {
        $v = $val2.GetValue("DeferFeatureUpdatesPeriodInDays")
        if ($v -ne "0") {
            Set-ItemProperty -Path $key2 -Name "DeferFeatureUpdatesPeriodInDays" -Value "0" -Verbose
            Write-Log "  Sifirlandi: DeferFeatureUpdatesPeriodInDays (eski: $v)"
        } else { Write-Log "  Zaten 0: DeferFeatureUpdatesPeriodInDays" }
    }
} else {
    Write-Log "  Yok: $key2"
}

$key3 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (Test-Path $key3) {
    $val3 = Get-Item $key3 -EA Ignore
    $props3 = $val3.Property

    if ($props3 -contains "AllowDeviceNameInTelemetry") {
        $v = $val3.GetValue("AllowDeviceNameInTelemetry")
        if ($v -ne "1") {
            Set-ItemProperty -Path $key3 -Name "AllowDeviceNameInTelemetry" -Value "1" -Verbose
            Write-Log "  Duzenlendi: AllowDeviceNameInTelemetry -> 1 (eski: $v)"
        } else { Write-Log "  Zaten 1: AllowDeviceNameInTelemetry" }
    } else {
        New-ItemProperty -Path $key3 -PropertyType DWORD -Name "AllowDeviceNameInTelemetry" -Value "1" -Verbose
        Write-Log "  Olusturuldu: AllowDeviceNameInTelemetry = 1"
    }

    if ($props3 -contains "AllowTelemetry_PolicyManager") {
        $v = $val3.GetValue("AllowTelemetry_PolicyManager")
        if ($v -ne "1") {
            Set-ItemProperty -Path $key3 -Name "AllowTelemetry_PolicyManager" -Value "1" -Verbose
            Write-Log "  Duzenlendi: AllowTelemetry_PolicyManager -> 1 (eski: $v)"
        } else { Write-Log "  Zaten 1: AllowTelemetry_PolicyManager" }
    } else {
        New-ItemProperty -Path $key3 -PropertyType DWORD -Name "AllowTelemetry_PolicyManager" -Value "1" -Verbose
        Write-Log "  Olusturuldu: AllowTelemetry_PolicyManager = 1"
    }
} else {
    Write-Log "  Yok: $key3"
}

$key4 = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Appraiser\GWX"
if (Test-Path $key4) {
    $val4 = Get-Item $key4 -EA Ignore
    if ($val4.Property -contains "GStatus") {
        $v = $val4.GetValue("GStatus")
        if ($v -ne "2") {
            Set-ItemProperty -Path $key4 -Name "GStatus" -Value "2" -Verbose
            Write-Log "  Duzenlendi: GStatus -> 2 (eski: $v)"
        } else { Write-Log "  Zaten 2: GStatus" }
    } else {
        New-ItemProperty -Path $key4 -PropertyType DWORD -Name "GStatus" -Value "2" -Verbose
        Write-Log "  Olusturuldu: GStatus = 2"
    }
} else {
    Write-Log "  Yok: $key4"
}

Write-Log "Adim 1/10 - Tamamlandi"

# --- Servisleri durdur ---
Write-Log "Adim 2/10 - Windows Update servisleri durduruluyor..."
Stop-Service -Name BITS -Force -Verbose -ErrorAction SilentlyContinue
Stop-Service -Name wuauserv -Force -Verbose -ErrorAction SilentlyContinue
Stop-Service -Name cryptsvc -Force -Verbose -ErrorAction SilentlyContinue
Stop-Service -Name usosvc -Force -Verbose -ErrorAction SilentlyContinue
Stop-Service -Name WaaSMedicSvc -Force -Verbose -ErrorAction SilentlyContinue
Write-Log "Adim 2/10 - Tamamlandi (BITS, wuauserv, cryptsvc, usosvc, WaaSMedicSvc durduruldu)"

# --- QMGR temizlik ---
Write-Log "Adim 3/10 - QMGR veri dosyasi temizleniyor..."
Remove-Item -Path "$env:allusersprofile\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -ErrorAction SilentlyContinue -Verbose
Write-Log "Adim 3/10 - Tamamlandi"

# --- SoftwareDistribution ve Catroot2 hard silme ---
Write-Log "Adim 4/10 - Guncelleme onbellegi hard siliniyor..."
foreach ($folder in @("$env:systemroot\SoftwareDistribution", "$env:systemroot\System32\Catroot2")) {
    if (Test-Path -LiteralPath $folder) {
        $deleted = $false
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            if ($folder -like "*Catroot2") {
                Stop-Service -Name cryptsvc -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            & cmd.exe /c rd /s /q "$folder" 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
            if (-not (Test-Path -LiteralPath $folder)) { $deleted = $true; break }
            Write-Log "  Deneme $attempt/5 kilitli, tekrar deneniyor..."
            Start-Sleep -Seconds 2
        }
        if ($deleted) {
            Write-Log "  Silindi: $folder"
        } elseif ($folder -like "*Catroot2") {
            Rename-Item -LiteralPath $folder -NewName "Catroot2.old" -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $folder)) {
                Write-Log "  Silinemedi, Catroot2.old olarak yeniden adlandirildi (cryptsvc yenisini olusturacak)"
            } else {
                Write-Log "  Silinemedi ve yeniden adlandirilemedi: $folder"
            }
        } else {
            Write-Log "  Silinemedi: $folder (kilitli dosya olabilir)"
        }
    } else {
        Write-Log "  Yok: $folder"
    }
}
Write-Log "Adim 4/10 - Tamamlandi (SoftwareDistribution, Catroot2 hard silindi)"

# --- Servis izinlerini sifirla ---
Write-Log "Adim 5/10 - Servis izinleri sifirlaniyor..."
Start-Process "sc.exe" -ArgumentList "sdset bits D:(A;CI;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)" -Wait
Start-Process "sc.exe" -ArgumentList "sdset wuauserv D:(A;;CCLCSWRPLORC;;;AU)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)" -Wait
Write-Log "Adim 5/10 - Tamamlandi"

# --- DLL kaydi ---
Write-Log "Adim 6/10 - DLL'ler yeniden kaydediliyor..."
Set-Location $env:systemroot\system32
$dlls = @(
    "atl.dll","urlmon.dll","mshtml.dll","shdocvw.dll","browseui.dll",
    "jscript.dll","vbscript.dll","scrrun.dll","msxml.dll","msxml3.dll",
    "msxml6.dll","actxprxy.dll","softpub.dll","wintrust.dll","dssenh.dll",
    "rsaenh.dll","gpkcsp.dll","sccbase.dll","slbcsp.dll","cryptdlg.dll",
    "oleaut32.dll","ole32.dll","shell32.dll","initpki.dll","wuapi.dll",
    "wuaueng.dll","wuaueng1.dll","wucltui.dll","wups.dll","wups2.dll",
    "wuweb.dll","qmgr.dll","qmgrprxy.dll","wucltux.dll","muweb.dll","wuwebv.dll"
)
$dllCount = 0
foreach ($dll in $dlls) {
    regsvr32.exe $dll /s
    $dllCount++
}
Write-Log "Adim 6/10 - Tamamlandi ($dllCount DLL kaydedildi)"

# --- Winsock sifirla ---
Write-Log "Adim 7/10 - Winsock sifirlaniyor..."
netsh winsock reset
Write-Log "Adim 7/10 - Tamamlandi"

# --- Servisleri baslat ---
Write-Log "Adim 8/10 - Windows Update servisleri baslatiliyor..."
Start-Service -Name BITS -Verbose
Start-Service -Name wuauserv -Verbose
Start-Service -Name cryptsvc -Verbose
Start-Service -Name usosvc -Verbose -ErrorAction SilentlyContinue
Start-Service -Name WaaSMedicSvc -Verbose -ErrorAction SilentlyContinue
Write-Log "Adim 8/10 - Tamamlandi"

# --- USOClient ile tarama baslat ---
Write-Log "Adim 9/10 - Guncelleme taramasi baslatiliyor (USOClient)..."
USOClient.exe StartInteractiveScan
Write-Log "Adim 9/10 - Tarama baslatildi, 5 dakika bekleniyor..."
Start-Sleep -Seconds 300
Write-Log "Adim 9/10 - Bekleme tamamlandi"

# --- SetupDiag ile log ---
Write-Log "Adim 10/10 - SetupDiag ile tani logu olusturuluyor..."
try {
    $setupDiagUrl = "https://go.microsoft.com/fwlink/?linkid=870142"
    $setupDiagPath = "$logDir\SetupDiag.exe"
    $diagOutput = "$logDir\#Windows Updates - Diagnostics.log"

    $webClient = New-Object System.Net.WebClient
    Write-Log "  SetupDiag indiriliyor..."
    $webClient.DownloadFile($setupDiagUrl, $setupDiagPath)
    Write-Log "  Indirme tamamlandi"

    $checkLogs = Test-Path -Path "$logDir\logs*.zip"
    if ($checkLogs) {
        Remove-Item -Path "$logDir\logs*.zip" -Force -Recurse
        Write-Log "  Eski log zip'leri temizlendi"
    }

    Write-Log "  SetupDiag calistiriliyor..."
    ."$setupDiagPath" /Output:"$diagOutput"
    Write-Log "  Tani logu olusturuldu: $diagOutput"
}
catch {
    Write-Log "  SetupDiag basarisiz: $($_.Exception.Message)"
}
Write-Log "Adim 10/10 - Tamamlandi"

Write-Log "=== Windows Update Remediation Tamamlandi ==="
exit 0
