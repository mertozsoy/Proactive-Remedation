$LogFolder = "C:\Temp"
$LogFile = "$LogFolder\Google_Earth_Pro_Removal.log"
$AppGUID = "{E3B69BB6-FFD8-441C-933E-BB8A3136ED8F}"

if (!(Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

$TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-Content -Path $LogFile -Value "[$TimeStamp] Remediation basladi."

$Found = Get-ChildItem `
"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
Where-Object { $_.PSChildName -eq $AppGUID }

if ($Found) {

    Add-Content -Path $LogFile -Value "[$TimeStamp] Google Earth Pro bulundu. Kaldirma baslatiliyor."

    $Process = Start-Process msiexec.exe `
        -ArgumentList "/X $AppGUID /quiet /norestart" `
        -Wait `
        -PassThru

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Add-Content -Path $LogFile -Value "[$TimeStamp] Msiexec ExitCode: $($Process.ExitCode)"

    Start-Sleep -Seconds 10

    $StillExists = Get-ChildItem `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -eq $AppGUID }

    if ($StillExists) {
        Add-Content -Path $LogFile -Value "[$TimeStamp] Kaldirma basarisiz."
    }
    else {
        Add-Content -Path $LogFile -Value "[$TimeStamp] Kaldirma basarili."
    }
}
else {
    Add-Content -Path $LogFile -Value "[$TimeStamp] Uygulama zaten kurulu degil."
}
