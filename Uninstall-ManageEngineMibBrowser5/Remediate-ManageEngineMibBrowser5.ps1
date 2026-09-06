$LogFolder = "C:\Temp"
$LogFile = "$LogFolder\ManageEngine_MibBrowser_5_Removal.log"
$AppGUID = "{9C79392A-ACA0-4253-A57A-B29A53205273}"

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

    Add-Content -Path $LogFile -Value "[$TimeStamp] ManageEngine MibBrowser 5 bulundu. Kaldirma baslatiliyor."

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
