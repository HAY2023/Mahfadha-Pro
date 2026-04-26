Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile("H:\Mahfadha-Pro\chrome-extension\icons\icon128.png")
$bmp48 = New-Object System.Drawing.Bitmap($img, 48, 48)
$bmp48.Save("H:\Mahfadha-Pro\chrome-extension\icons\icon48.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp16 = New-Object System.Drawing.Bitmap($img, 16, 16)
$bmp16.Save("H:\Mahfadha-Pro\chrome-extension\icons\icon16.png", [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
$bmp48.Dispose()
$bmp16.Dispose()
Write-Host "Icons resized successfully."
