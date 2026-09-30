$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Drawing
# Lowercase wordmark, using the Windows UI font family already on the device.
$sizes=@(16,24,32,48,64,128,256)
$images=@()
foreach ($size in $sizes) {
 $bmp=New-Object Drawing.Bitmap($size,$size)
 $g=[Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode='AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
 $g.ScaleTransform($size/64.0,$size/64.0)
 $ink=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#0D1B2A'))
 $textBrush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#E0E1DD'))
 $tile=New-Object Drawing.Drawing2D.GraphicsPath
 $tile.AddArc(0,0,16,16,180,90);$tile.AddArc(48,0,16,16,270,90)
 $tile.AddArc(48,48,16,16,0,90);$tile.AddArc(0,48,16,16,90,90);$tile.CloseFigure()
 $g.FillPath($ink,$tile)
 $family=New-Object Drawing.FontFamily('Segoe UI Semibold')
 $glyphs=New-Object Drawing.Drawing2D.GraphicsPath
 $glyphs.AddString('ctc',$family,[int][Drawing.FontStyle]::Regular,44,[Drawing.PointF]::new(0,0),[Drawing.StringFormat]::GenericTypographic)
 $bounds=$glyphs.GetBounds();$fit=[Math]::Min(56/$bounds.Width,30/$bounds.Height)
 $transform=New-Object Drawing.Drawing2D.Matrix
 $transform.Translate([single](32-($bounds.X+$bounds.Width/2)*$fit),[single](32-($bounds.Y+$bounds.Height/2)*$fit))
 $transform.Scale([single]$fit,[single]$fit)
 $glyphs.Transform($transform);$g.FillPath($textBrush,$glyphs)
 $memory=New-Object IO.MemoryStream; $bmp.Save($memory,[Drawing.Imaging.ImageFormat]::Png); $images+=,@($memory.ToArray())
 if($size -eq 256){$bmp.Save((Join-Path $PSScriptRoot 'ctc-logo.png'),[Drawing.Imaging.ImageFormat]::Png)}
 $memory.Dispose(); $g.Dispose(); $bmp.Dispose(); $ink.Dispose(); $textBrush.Dispose();$tile.Dispose();$glyphs.Dispose();$family.Dispose();$transform.Dispose()
}
$stream=[IO.File]::Create((Join-Path $root 'Context.ico')); $writer=New-Object IO.BinaryWriter($stream)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
$offset=6+16*$sizes.Count
for ($i=0;$i -lt $sizes.Count;$i++) { $dim=if ($sizes[$i] -eq 256) {0} else {$sizes[$i]}; $writer.Write([byte]$dim); $writer.Write([byte]$dim); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset); $offset+=$images[$i].Length }
foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }; $writer.Dispose()
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
foreach ($name in @('ContextWidget','Setup')) {
 & $compiler /nologo /target:winexe /optimize+ "/win32icon:$root\Context.ico" /reference:System.Windows.Forms.dll "/out:$root\$name.exe" (Join-Path $PSScriptRoot 'Launcher.cs')
 if ($LASTEXITCODE) { throw "Compilation failed: $name" }
}
