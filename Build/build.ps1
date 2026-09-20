$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Drawing
# Original CTC monogram. Geometry stays legible at tray sizes.
$sizes=@(16,24,32,48,64,128,256)
$images=@()
foreach ($size in $sizes) {
 $bmp=New-Object Drawing.Bitmap($size,$size)
 $g=[Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode='AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
 $g.ScaleTransform($size/64.0,$size/64.0)
 $ink=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#0D1B2A'))
 $frost=New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#778DA9'),7)
 $snow=New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#E0E1DD'),6)
 $frost.StartCap='Round'; $frost.EndCap='Round'; $snow.StartCap='Round'; $snow.EndCap='Round'
 $g.FillEllipse($ink,0,0,64,64)
 # Three distinct letter stems; the T crossbar links the C openings.
 $frost.Width=5; $snow.Width=5
 $g.DrawArc($frost,6,18,17,28,48,264)
 $g.DrawLine($snow,23,20,42,20)
 $g.DrawLine($snow,32,20,32,45)
 $g.DrawArc($frost,41,18,17,28,48,264)
 $memory=New-Object IO.MemoryStream; $bmp.Save($memory,[Drawing.Imaging.ImageFormat]::Png); $images+=,@($memory.ToArray())
 $memory.Dispose(); $g.Dispose(); $bmp.Dispose(); $ink.Dispose(); $frost.Dispose(); $snow.Dispose()
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
