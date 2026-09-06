# Uygulama klasör yolu
$uygulamaYolu = "Uygulamanin kurulu oldugu klasor yolu"

# Calistirilacak exe dosya adi
$uygulamaAdi = "UygulamaExeAdi.exe"

# Uygulamanin tam dosya yolu
$hedefYol = Join-Path $uygulamaYolu $uygulamaAdi

# Tum kullanicilar icin Baslangic (Startup) klasoru
$baslangicKlasoru = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"

# Olusturulacak kisayolun yolu
$kisayolYolu = Join-Path $baslangicKlasoru ($uygulamaAdi.Replace(".exe", ".lnk"))

# Windows Script Host nesnesi olusturulur
$WshShell = New-Object -ComObject WScript.Shell

# Kisayol olusturulur
$kisayol = $WshShell.CreateShortcut($kisayolYolu)
$kisayol.TargetPath = $hedefYol
$kisayol.WorkingDirectory = $uygulamaYolu
$kisayol.Save()
