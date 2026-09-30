# SPDX-License-Identifier: MIT
param([string]$TestRoot='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,System.Windows.Forms
. (Join-Path $PSScriptRoot 'Install.Core.ps1')
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Install Context-Token Codex" Width="600" Height="550" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Background="#0D1B2A" Foreground="#E0E1DD">
 <Grid Margin="28"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Orientation="Horizontal" Margin="0,0,0,20"><Image x:Name="Logo" Width="52" Height="52" Margin="0,0,16,0"/><StackPanel><TextBlock Text="Context-Token Codex" FontSize="28" FontWeight="SemiBold"/><TextBlock Text="Setup 6.8.0  /  Windows" Foreground="#778DA9" FontSize="12"/></StackPanel></StackPanel>
  <Grid Grid.Row="1">
   <StackPanel x:Name="Welcome"><TextBlock Text="Monitor your active chats." FontSize="22" Margin="0,0,0,16"/><TextBlock Text="Read context and token records. Check compaction status. Edit context limits. Use the tray icon to restore the widget." Margin="0,0,0,14"/><TextBlock Text="CTC installs for your Windows account. Windows supplies the required runtime. CTC keeps your Codex chats and settings in their current locations."/><TextBlock x:Name="Size" Foreground="#778DA9" Margin="0,20,0,0"/></StackPanel>
   <StackPanel x:Name="Options" Visibility="Collapsed"><TextBlock Text="Choose your setup" FontSize="22" Margin="0,0,0,16"/><TextBlock Text="Installation folder"/><DockPanel Margin="0,5,0,16"><Button x:Name="Browse" DockPanel.Dock="Right" Content="Browse" Margin="8,0,0,0"/><TextBox x:Name="Destination" Padding="8"/></DockPanel><CheckBox x:Name="Startup" IsChecked="True" Content="Auto-open with ChatGPT or Codex (watcher starts at sign-in)" Margin="0,0,0,12"/><CheckBox x:Name="Desktop" IsChecked="True" Content="Create a desktop shortcut" Margin="0,0,0,12"/><CheckBox x:Name="Launch" IsChecked="True" Content="Open the widget after installation" Margin="0,0,0,12"/><TextBlock Text="Auto-open is on by default. To disable it, clear the option here or in Widget settings. CTC keeps a backup when you install an update." Foreground="#778DA9"/></StackPanel>
   <StackPanel x:Name="Done" Visibility="Collapsed"><TextBlock Text="Ready to use." FontSize="26" Margin="0,0,0,20"/><TextBlock x:Name="Summary"/><TextBlock Text="To restore CTC, select the ctc icon beside the clock. Select Edit context limits to change context settings. Select the gear to change widget settings." Margin="0,20,0,0"/></StackPanel>
  </Grid>
  <StackPanel Grid.Row="2"><TextBlock x:Name="ErrorLabel" Foreground="#778DA9" Margin="0,8,0,8"/><StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="Back" Content="Back" Visibility="Collapsed" Margin="0,0,8,0"/><Button x:Name="Next" Content="Next" MinWidth="100"/></StackPanel></StackPanel>
 </Grid>
</Window>
'@
$w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$theme=New-Object Windows.ResourceDictionary; $theme.set_Source([Uri]::new((Join-Path $PSScriptRoot 'Theme.xaml'))); $w.Resources.MergedDictionaries.Add($theme)
$decoder=[Windows.Media.Imaging.BitmapDecoder]::Create([Uri]::new((Join-Path $PSScriptRoot 'Context.ico')),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
$w.Icon=$decoder.Frames[$decoder.Frames.Count-1]
$w.FindName('Logo').Source=$w.Icon
foreach ($name in @('Welcome','Options','Done','Destination','Startup','Desktop','Launch','Summary','ErrorLabel','Back','Next')) { Set-Variable $name $w.FindName($name) }
$Destination.Text=if ($TestRoot) { Join-Path $TestRoot 'installed' } else { Join-Path $env:LOCALAPPDATA 'Programs\ContextWidget' }
$w.FindName('Size').Text='File size: {0:N0} KB. Windows supplies PowerShell and .NET.' -f ((Get-ChildItem $PSScriptRoot -File|Measure-Object Length -Sum).Sum/1KB)
$script:page=0
$w.FindName('Browse').Add_Click({ $picker=New-Object Windows.Forms.FolderBrowserDialog; $picker.Description='Select the Context-Token Codex installation folder.'; if ($picker.ShowDialog() -eq 'OK') { $Destination.Text=Join-Path $picker.SelectedPath 'ContextWidget' }; $picker.Dispose() })
$Back.Add_Click({$Options.Visibility='Collapsed';$Welcome.Visibility='Visible';$Back.Visibility='Collapsed';$Next.Content='Next';$script:page=0})
$Next.Add_Click({
 try {
  $ErrorLabel.Text=''
  if ($script:page -eq 0) { $Welcome.Visibility='Collapsed';$Options.Visibility='Visible';$Back.Visibility='Visible';$Next.Content='Install';$script:page=1;return }
  if ($script:page -eq 2) { $w.Close();return }
  $Next.IsEnabled=$false
  if (-not $TestRoot) {
   try { $stop=[Threading.EventWaitHandle]::OpenExisting(('Local\CodexContextWatcherStop-'+[Environment]::UserName)); [void]$stop.Set(); $stop.Dispose(); Start-Sleep -Milliseconds 250 } catch {}
   try { $event=[Threading.EventWaitHandle]::OpenExisting(('Local\CodexContextOverlayShow-'+[Environment]::UserName)); [void]$event.Set(); $event.Dispose(); Start-Sleep -Milliseconds 600 } catch {}
   foreach ($p in @(Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -in @('Codex Context Overlay','Context-Token Codex') })) { [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(5000)) { throw 'Close the running widget. Then select Install again.' } }
  }
  $installed=Install-ContextWidget -Source $PSScriptRoot -Destination $Destination.Text -AutoOpen ([bool]$Startup.IsChecked) -DesktopShortcut ([bool]$Desktop.IsChecked) -TestRoot $TestRoot
  $Options.Visibility='Collapsed';$Done.Visibility='Visible';$Back.Visibility='Collapsed';$Next.Content='Finish';$script:page=2
  $Summary.Text="Installed in $($installed.Destination)`n$($installed.Files) runtime files; $([Math]::Round($installed.Bytes/1KB)) KB.`nAuto-open: $($Startup.IsChecked)"
  if (-not $TestRoot) {
   if ($Startup.IsChecked) { Start-Process (Join-Path $installed.Destination 'ContextWidget.exe') -ArgumentList '/watch' -WindowStyle Hidden }
   if ($Launch.IsChecked) { Start-Process (Join-Path $installed.Destination 'ContextWidget.exe') }
  }
 } catch { $ErrorLabel.Text='Installation stopped: '+$_.Exception.Message } finally { $Next.IsEnabled=$true }
})
if ($TestRoot) {
 $w.Add_ContentRendered({
  $Next.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  $Next.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  [IO.File]::WriteAllText((Join-Path $TestRoot 'wizard-result.json'),(@{Page=$script:page;Error=$ErrorLabel.Text;AutoOpen=$Startup.IsChecked}|ConvertTo-Json))
  $w.Close()
 })
}
[void]$w.ShowDialog()
