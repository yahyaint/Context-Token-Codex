# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName PresentationFramework,PresentationCore,System.Drawing
. (Join-Path $root 'Branding.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$decoder=[Windows.Media.Imaging.BitmapDecoder]::Create([Uri]::new((Join-Path $root 'Context.ico')),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
$window=[Windows.Window]::new(); $image=[Windows.Controls.Image]::new(); $image.Width=32
foreach($case in @(@(1,32),@(1.25,48),@(1.5,48),@(2,64),@(3,128),@(8,256))){
 Set-CtcLogo $window $image $decoder $case[0]
 Assert ($image.Source.PixelWidth -eq $case[1]) "Incorrect logo frame at scale $($case[0])."
 Assert ([Windows.Media.RenderOptions]::GetBitmapScalingMode($image) -eq [Windows.Media.BitmapScalingMode]::HighQuality) 'Logo interpolation changed.'
}
# Compare the encoded image resources directly. Windows icon extraction can
# convert alpha differently in .NET Framework and .NET; that is not new artwork.
if(-not ('CtcIconResourceCheck' -as [type])){Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class CtcIconResourceCheck {
 delegate bool ResourceName(IntPtr module, IntPtr type, IntPtr name, IntPtr param);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
 [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool EnumResourceNames(IntPtr module,IntPtr type,ResourceName callback,IntPtr param);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindResource(IntPtr module,IntPtr name,IntPtr type);
 [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr module,IntPtr resource);
 [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr module,IntPtr resource);
 [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr resource);
 public static byte[][] Read(string path){
  var module=LoadLibraryEx(path,IntPtr.Zero,0x22);
  if(module==IntPtr.Zero)throw new InvalidOperationException("Cannot read launcher resources.");
  var images=new List<byte[]>();
  try {
   ResourceName callback=delegate(IntPtr h,IntPtr type,IntPtr name,IntPtr param){
    var resource=FindResource(h,name,type);var bytes=new byte[SizeofResource(h,resource)];
    Marshal.Copy(LockResource(LoadResource(h,resource)),bytes,0,bytes.Length);images.Add(bytes);return true;
   };
   if(!EnumResourceNames(module,new IntPtr(3),callback,IntPtr.Zero))throw new InvalidOperationException("Launcher icons are missing.");
  }finally{FreeLibrary(module);}
  return images.ToArray();
 }
}
'@}
$ico=[IO.File]::ReadAllBytes((Join-Path $root 'Context.ico')); $count=[BitConverter]::ToUInt16($ico,4)
$expected=@(); for($index=0;$index -lt $count;$index++){
 $length=[BitConverter]::ToUInt32($ico,6+16*$index+8); $offset=[BitConverter]::ToUInt32($ico,6+16*$index+12)
 $expected+=[Convert]::ToBase64String($ico,$offset,$length)
}
foreach($name in @('ContextWidget.exe','Setup.exe')){
 $actual=@([CtcIconResourceCheck]::Read((Join-Path $root $name))|ForEach-Object {[Convert]::ToBase64String($_)})
 Assert ($actual.Count -eq $expected.Count) "Icon frame count differs: $name."
 Assert (@(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count -eq 0) "Icon image resources differ: $name."
}
'PASS: DPI frame selection, image interpolation, identical launcher, setup and file icon image resources.'
