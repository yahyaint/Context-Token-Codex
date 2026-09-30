# SPDX-License-Identifier: MIT
# Use the same multi-size icon as the launcher. Avoid scaling the largest
# bitmap down with WPF's default low-quality image interpolation.
function Get-CtcLogoFrame($Decoder,[double]$Size,[double]$Scale=1) {
    $pixels=[Math]::Ceiling($Size*[Math]::Max([double]1,$Scale))
    $frames=@($Decoder.Frames | Sort-Object PixelWidth)
    foreach($frame in $frames){if($frame.PixelWidth -ge $pixels){return $frame}}
    return $frames[$frames.Count-1]
}
function Set-CtcLogo($Window,$Image,$Decoder,[double]$Scale=0) {
    if($Scale -le 0){
        $handle=([Windows.Interop.WindowInteropHelper]::new($Window)).Handle
        $source=if($handle -ne [IntPtr]::Zero){[Windows.Interop.HwndSource]::FromHwnd($handle)}else{$null}
        $Scale=if($source -and $source.CompositionTarget){$source.CompositionTarget.TransformToDevice.M11}else{1}
    }
    $Image.Source=Get-CtcLogoFrame $Decoder $Image.Width $Scale
    [Windows.Media.RenderOptions]::SetBitmapScalingMode($Image,[Windows.Media.BitmapScalingMode]::HighQuality)
    $Image.UseLayoutRounding=$true; $Image.SnapsToDevicePixels=$true
}
