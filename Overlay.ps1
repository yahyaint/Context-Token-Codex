# SPDX-License-Identifier: MIT
param([switch]$Watch, [string]$CodexHome='', [string]$PreferencesPath='', [int]$TestSeconds=0, [string]$TestReport='', [switch]$TestSettings)
$ErrorActionPreference = 'Stop'
if ($TestSettings -and ($TestSeconds -lt 1 -or -not $CodexHome -or -not (Test-Path -LiteralPath (Join-Path $CodexHome '.overlay-test-fixture')))) { throw 'Settings test requires a marked disposable fixture and TestSeconds.' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
# Load bytes so the identity bridge does not keep the launcher locked on disk.
[void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'ContextWidget.exe')))
[void][WidgetIdentity]::SetCurrentProcessExplicitAppUserModelID('Community.ContextWidget')
$script:folder = $PSScriptRoot
if (-not $PreferencesPath) { $PreferencesPath = Join-Path $env:LOCALAPPDATA 'CodexContextMonitor\overlay.json' }
$script:preferencesPath = $PreferencesPath
$script:prefs = @{ Topmost=$true; Target='Either'; AutoOpen=$true; Width=460; Height=620; Left=-1; Top=-1; Compact=$true; Opacity=0.92; Corner='BottomRight';Mode='Context' }
. (Join-Path $PSScriptRoot 'Monitor.Data.ps1')
$script:prefs=Read-WidgetPreferences $PreferencesPath $script:prefs
function Save-Preferences {
    [void][IO.Directory]::CreateDirectory((Split-Path $script:preferencesPath -Parent))
    [IO.File]::WriteAllText($script:preferencesPath, ($script:prefs | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}
. (Join-Path $PSScriptRoot 'Monitor.Data.ps1')
. (Join-Path $PSScriptRoot 'Usage.Provider.ps1')
$suffix = if ($TestSeconds -gt 0) { "Test-$PID" } else { [Environment]::UserName }
$mutex = New-Object Threading.Mutex($false, "Local\CodexContextOverlay-$suffix")
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) {
    # Existing tray instance notices this event and restores its window.
    try { $existing = [Threading.EventWaitHandle]::OpenExisting("Local\CodexContextOverlayShow-$suffix"); [void]$existing.Set(); $existing.Dispose() } catch { }
    $mutex.Dispose(); exit
}
$showEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, "Local\CodexContextOverlayShow-$suffix")
$readyEvent=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,"Local\CodexContextOverlayReady-$suffix")
$readyEvent.Reset() | Out-Null
$script:shared = [hashtable]::Synchronized(@{ Stop=$false; Latest=$null; Error=''; Scans=0; Mode=$prefs.Mode; LiveQuota=$null; QuotaError=''; RefreshQuota=$false; Fetching=$false })
$worker = [PowerShell]::Create()
[void]$worker.AddScript({
    param($shared,$folder,$homePath)
    try {
        . (Join-Path $folder 'Monitor.Core.ps1') -CodexHome $homePath
        . (Join-Path $folder 'Monitor.Data.ps1')
        . (Join-Path $folder 'Restart.Core.ps1')
        . (Join-Path $folder 'Usage.Provider.ps1')
        while (-not $shared.Stop) {
            try { $snapshot=Get-MonitorSnapshot -QuickStart:($shared.Scans -eq 0); Update-SnapshotQuota $snapshot $shared.LiveQuota $CodexHome; $shared.Latest=$snapshot; $shared.Error=''; $shared.Scans++ }
            catch { $shared.Error=$_.Exception.Message }
            for ($i=0; $i -lt 5 -and -not $shared.Stop; $i++) { Start-Sleep -Milliseconds 200 }
        }
    } catch { $shared.Error=$_.Exception.Message }
}).AddArgument($script:shared).AddArgument($PSScriptRoot).AddArgument($CodexHome)
$workerResult = $worker.BeginInvoke()
$quotaWorker=[PowerShell]::Create()
[void]$quotaWorker.AddScript({
    param($shared,$folder,$homePath,$testing)
    . (Join-Path $folder 'Usage.Provider.ps1')
    $last=[DateTime]::MinValue
    while (-not $shared.Stop) {
        if (-not $testing -and ($shared.RefreshQuota -or ([DateTime]::UtcNow-$last).TotalSeconds -ge 60)) {
            $shared.RefreshQuota=$false; $shared.Fetching=$true
            try { $shared.LiveQuota=Get-CodexRateLimits $homePath; $shared.QuotaError='' } catch { $shared.QuotaError=$_.Exception.Message }
            finally { $shared.Fetching=$false; $last=[DateTime]::UtcNow }
        }
        Start-Sleep -Milliseconds 500
    }
}).AddArgument($shared).AddArgument($PSScriptRoot).AddArgument($CodexHome).AddArgument(($TestSeconds -gt 0))
$quotaTask=$quotaWorker.BeginInvoke()
# Settings run on the UI thread; only the worker reads rollout files.
$script:coreError = ''
try { . (Join-Path $PSScriptRoot 'Monitor.Core.ps1') -CodexHome $CodexHome; . (Join-Path $PSScriptRoot 'Restart.Core.ps1') } catch { $script:coreError=$_.Exception.Message }
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Context-Token Codex" Width="460" Height="620" MinWidth="300" MinHeight="150" Background="Transparent" Foreground="#E0E1DD" WindowStyle="None" AllowsTransparency="True" ResizeMode="NoResize" WindowStartupLocation="Manual">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="10,6"/><Setter Property="Margin" Value="0,0,6,0"/><Setter Property="Background" Value="#0D1B2A"/><Setter Property="Foreground" Value="#E0E1DD"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Chrome" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#778DA9"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#778DA9"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
 </Window.Resources>
 <Border BorderBrush="#778DA9" BorderThickness="1" CornerRadius="18" Padding="16">
 <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#0D1B2A" Offset="0"/><GradientStop Color="#0D1B2A" Offset="1"/></LinearGradientBrush></Border.Background>
 <Grid>
 <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <Grid x:Name="DragHandle" Background="Transparent" Margin="0,0,0,9" Cursor="SizeAll" ToolTip="Drag the header to move the widget. Release near a corner to set its position.">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Image x:Name="BrandIcon" Width="32" Height="32" HorizontalAlignment="Left" VerticalAlignment="Center" ToolTip="Context-Token Codex"/>
  <StackPanel Grid.Column="1" Orientation="Horizontal">
   <Button x:Name="ToggleButton" Content="Expand" Padding="7,3" Margin="0,0,5,0" FontSize="11" ToolTip="Change between the compact view and expanded view."/>
   <Button x:Name="DirectTray" Content="Tray" Padding="7,3" Margin="0,0,5,0" FontSize="11" ToolTip="Hide the widget in the tray. To restore the widget, select the ctc icon beside the clock."/><Button x:Name="QuickSettings" Width="28" Height="28" FontSize="12" FontFamily="Segoe MDL2 Assets" Content="&#xE713;" Padding="0" Margin="0,0,5,0" ToolTip="Widget settings"/>
   <Button x:Name="MinimizeButton" Width="28" Height="28" Padding="0" Margin="0,0,5,0" ToolTip="Minimize to taskbar"><Path Data="M0,5 L10,5" Width="10" Height="10" Stroke="#E0E1DD" StrokeThickness="1.5"/></Button>
   <Button x:Name="CloseButton" Width="28" Height="28" Padding="0" Margin="0" ToolTip="Exit CTC"><Path Data="M1,1 L9,9 M1,9 L9,1" Width="10" Height="10" Stroke="#E0E1DD" StrokeThickness="1.5"/></Button>
  </StackPanel>
 </Grid>
 <WrapPanel Grid.Row="1" Margin="0,0,0,12"><Button x:Name="ContextMode" Content="Context" Padding="12,5" Margin="0,0,6,0"/><Button x:Name="TokenMode" Content="Tokens" Padding="12,5" Margin="0,0,6,0"/><Button x:Name="LimitsMode" Content="Limits" Padding="12,5" ToolTip="Edit context settings"/></WrapPanel><DockPanel Grid.Row="2" Margin="0,0,0,10"><Button x:Name="RefreshUsage" DockPanel.Dock="Right" Content="&#xE72C;" FontFamily="Segoe MDL2 Assets" Width="28" Height="28" Padding="0" Margin="4,0,0,0" ToolTip="Refresh account quotas"/><UniformGrid x:Name="ContextQuotaBars" Columns="2"/></DockPanel><Grid Grid.Row="3">
 <StackPanel x:Name="MiniPanel" Background="Transparent">
  <TextBlock x:Name="MiniTitle" Text="No active chats" FontSize="17" FontWeight="SemiBold" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis" Cursor="Hand" ToolTip="Select the chat name to expand the widget."/>
  <TextBlock x:Name="MiniStatus" Text="Data check" FontSize="11" Foreground="#E0E1DD" Margin="0,5,0,6" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis"/>
  <Grid Margin="0,2,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="MiniPercent" Text="--" FontSize="30" FontWeight="SemiBold" Foreground="#778DA9"/><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="CONTEXT USED" FontSize="9" Foreground="#E0E1DD" HorizontalAlignment="Right"/><TextBlock x:Name="MiniUsage" Text="No usage record" FontSize="11" Foreground="#E0E1DD" HorizontalAlignment="Right"/></StackPanel></Grid>
  <ProgressBar x:Name="MiniBar" Height="6" Minimum="0" Maximum="100" Background="#0D1B2A" Foreground="#778DA9"/>
  <UniformGrid Columns="3" Margin="0,12,0,8">
   <StackPanel><TextBlock Text="REMAINING" FontSize="9" Foreground="#E0E1DD"/><TextBlock x:Name="MiniRemaining" Text="--" FontSize="15" Margin="0,3,0,0"/></StackPanel>
   <StackPanel><TextBlock Text="COMPACTIONS" FontSize="9" Foreground="#E0E1DD"/><TextBlock x:Name="MiniCompactions" Text="--" FontSize="15" Margin="0,3,0,0"/></StackPanel>
   <StackPanel><TextBlock Text="CACHED INPUT" FontSize="9" Foreground="#E0E1DD"/><TextBlock x:Name="MiniCached" Text="--" FontSize="15" Margin="0,3,0,0"/></StackPanel>
  </UniformGrid>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="MiniUpdated" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap" Text="No data record" FontSize="10" Foreground="#E0E1DD" VerticalAlignment="Center"/><Grid Grid.Column="1" Margin="8,0,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions><Button x:Name="PreviousTask" Grid.Column="0" Content="&#x2039;" Width="28" Height="28" Padding="0" Margin="0" ToolTip="Previous active chat"/><TextBlock x:Name="TaskPosition" Grid.Column="1" Text="0 / 0" MinWidth="40" TextAlignment="Center" FontSize="10" VerticalAlignment="Center" Margin="8,0"/><Button x:Name="NextTask" Grid.Column="2" Content="&#x203A;" Width="28" Height="28" Padding="0" Margin="0" ToolTip="Next active chat"/></Grid></Grid>
  <Button x:Name="MiniEditContext" Content="Edit context limits" FontSize="11" Padding="10,3" HorizontalAlignment="Left" Margin="0,8,0,0" IsEnabled="False" ToolTip="Edit the project for this chat. The settings apply to all models in that project."/><!-- mini shortcut --></StackPanel><ScrollViewer x:Name="TokensPanel" VerticalScrollBarVisibility="Auto" Visibility="Collapsed"><StackPanel Margin="0,0,8,0"><TextBlock x:Name="ActiveTokenHeading" Text="Active chats" FontSize="10" Foreground="#778DA9" Margin="0,0,0,6"/><StackPanel x:Name="ActiveTokenTasks"/><Expander x:Name="TokenSummary" Header="Recorded chats" Foreground="#E0E1DD" IsExpanded="True" Margin="0,0,0,8"><StackPanel>
  <DockPanel><TextBlock Text="Recorded totals" FontSize="10" Foreground="#778DA9"/><TextBlock x:Name="TokenLive" Text="Watching files" FontSize="10" HorizontalAlignment="Right"/></DockPanel>
  <TextBlock x:Name="TokenTotal" Text="No usage record" FontSize="28" FontWeight="SemiBold" Margin="0,4,0,4"/>
  <TextBlock x:Name="TokenBreakdown" FontSize="10" Opacity="0.75" Margin="0,0,0,8"/>
  <UniformGrid x:Name="TokenMetrics" Columns="3" Margin="0,0,0,8"/>
  </StackPanel></Expander><Expander Header="Other chat details" Foreground="#E0E1DD" Margin="0,0,0,8"><StackPanel x:Name="TokenTasks"/></Expander>

  <Expander Header="Data status" Margin="0,4,0,4"><TextBlock x:Name="TokenSource" Text="Reading subscription usage..." FontSize="10" Margin="0,4,0,6"/></Expander>
  <Expander Header="How counts work" Foreground="#E0E1DD"><TextBlock x:Name="TokenCoverage" FontSize="10" Opacity="0.85" Margin="0,6,0,0"/></Expander>
 </StackPanel></ScrollViewer>
 <ContentControl x:Name="SettingsHost" Visibility="Collapsed"/><DockPanel x:Name="FullPanel" Visibility="Collapsed">
  <StackPanel DockPanel.Dock="Top">
   <TextBlock Text="Active chats" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,4" ToolTip="Context-Token Codex"/>
   <WrapPanel Visibility="Collapsed"><Button x:Name="SettingsButton" Content="Context settings"/><Button x:Name="TrayButton" Content="Park at edge"/><CheckBox x:Name="Pin" Content="On top" Foreground="#E0E1DD" VerticalAlignment="Center"/></WrapPanel>
   <TextBlock x:Name="Health" Text="Connecting to local Codex data..." Foreground="#E0E1DD" FontSize="10" Margin="0,0,0,10"/>
  </StackPanel>
  <StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">

   <TextBlock Text="Last context record" ToolTip="Codex writes usage records after requests. CTC reads local chats." FontSize="10" Foreground="#778DA9" Margin="0,5,0,0"/>
  </StackPanel>
  <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Cards"/></ScrollViewer>
 </DockPanel>
 </Grid>
 <StackPanel Grid.Row="4" Margin="0,12,0,0"><TextBlock x:Name="AuthorLine" Text="By Yahya Nabil" FontSize="10" Opacity="0.75" HorizontalAlignment="Center" Margin="0,0,0,8"/>
  <Border Height="1" Background="#0D1B2A" Margin="0,0,0,10"/>
  <Grid x:Name="AppearanceControls"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Background" FontSize="11" Foreground="#E0E1DD" VerticalAlignment="Center" Margin="0,0,10,0"/><Slider x:Name="LiveOpacity" Grid.Column="1" Minimum="40" Maximum="100" SmallChange="1" LargeChange="5" VerticalAlignment="Center" ToolTip="Drag to change the background opacity."/><TextBlock x:Name="LiveOpacityLabel" Grid.Column="2" Width="38" TextAlignment="Right" FontSize="11" VerticalAlignment="Center"/></Grid>
  <Grid Margin="0,9,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Grid.Column="1" FontSize="9" HorizontalAlignment="Center" VerticalAlignment="Center"><Hyperlink x:Name="UserWebsite" NavigateUri="https://yahyanabil.com" Foreground="#778DA9">yahyanabil.com</Hyperlink></TextBlock><StackPanel Orientation="Horizontal"><Button x:Name="QuickPin" Content="Pinned" FontSize="10" Padding="7,4" ToolTip="Keep the widget above other windows."/><Button x:Name="QuickCorner" Content="Corner" FontSize="10" Padding="7,4" Margin="5,0,0,0" ToolTip="Select a screen corner."/></StackPanel><StackPanel Grid.Column="2" Orientation="Horizontal"><Button x:Name="ParkButton" Content="Park bar" FontSize="10" Padding="8,4" Margin="5,0,0,0" ToolTip="Show a small bar at the same corner. Select its restore button to open the widget."/></StackPanel></Grid>
 </StackPanel>
 <Thumb x:Name="ResizeGrip" Grid.Row="3" Width="16" Height="16" HorizontalAlignment="Right" VerticalAlignment="Bottom" Cursor="SizeNWSE" Visibility="Collapsed" ToolTip="Drag to resize">
  <Thumb.Template><ControlTemplate TargetType="Thumb"><TextBlock Text="&#x25E2;" Foreground="#E0E1DD" Background="Transparent"/></ControlTemplate></Thumb.Template>
 </Thumb>
 </Grid>
 </Border>
</Window>
'@
$script:window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$window.Add_ContentRendered({[void]$readyEvent.Set()})
$script:theme=New-Object Windows.ResourceDictionary
$theme.set_Source([Uri]::new((Join-Path $PSScriptRoot 'Theme.xaml')))
$window.Resources.MergedDictionaries.Add($theme)
function Apply-WidgetTheme($element) {
    if ($element -is [Windows.Controls.ScrollViewer] -and $element.Tag -ne 'CTC.PixelScroll') {
        $element.Tag='CTC.PixelScroll'; $element.CanContentScroll=$false
        $element.Add_PreviewMouseWheel({
            param($viewer,$eventArgs)
            $source=$eventArgs.OriginalSource
            while ($source -and $source -ne $viewer) {
                if ($source -is [Windows.Controls.ComboBox] -and $source.IsDropDownOpen) { return }
                if ($source -is [Windows.Controls.ScrollViewer]) { return }
                try { $source=[Windows.Media.VisualTreeHelper]::GetParent($source) } catch { $source=$null }
            }
            $distance=[Math]::Max(-96.0,[Math]::Min(96.0,24.0*$eventArgs.Delta/120.0))
            $viewer.ScrollToVerticalOffset([Math]::Max(0.0,[Math]::Min($viewer.ScrollableHeight,$viewer.VerticalOffset-$distance)))
            $eventArgs.Handled=$true
        })
    }
    if ($element -is [Windows.FrameworkElement]) {
        $style=$theme[$element.GetType()]
        if ($style -and $element -isnot [Windows.Controls.TextBlock]) { $element.Style=$style }
    }
    if ($element -is [Windows.DependencyObject]) {
        foreach ($child in @([Windows.LogicalTreeHelper]::GetChildren($element))) {
            if ($child -is [Windows.DependencyObject]) { Apply-WidgetTheme $child }
        }
    }
}
Apply-WidgetTheme $window
$iconDecoder=[Windows.Media.Imaging.BitmapDecoder]::Create([Uri]::new((Join-Path $PSScriptRoot 'Context.ico')),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad); $window.Icon=$iconDecoder.Frames[$iconDecoder.Frames.Count-1]; $window.FindName('BrandIcon').Source=$window.Icon
foreach ($name in @('MiniEditContext','SettingsButton','TrayButton','Pin','Health','ContextQuotaBars','Cards','DragHandle','ToggleButton','QuickSettings','MinimizeButton','CloseButton','MiniPanel','FullPanel','MiniTitle','MiniStatus','MiniBar','MiniUsage','ResizeGrip','MiniPercent','MiniRemaining','MiniCompactions','MiniCached','MiniUpdated','PreviousTask','NextTask','TaskPosition','LiveOpacity','LiveOpacityLabel','QuickPin','QuickCorner','ParkButton','DirectTray','SettingsHost','ContextMode','TokenMode','LimitsMode','TokensPanel','TokenTotal','TokenLive','TokenMetrics','TokenTasks','ActiveTokenTasks','ActiveTokenHeading','TokenSummary','TokenBreakdown','TokenCoverage','TokenSource','RefreshUsage','AuthorLine','UserWebsite')) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }
$window.Width=[Math]::Max(360,[double]$prefs.Width); $window.Height=[Math]::Max(300,[double]$prefs.Height)
$area=[Windows.SystemParameters]::WorkArea
$hasSavedPosition=($prefs.Left -ne -1 -or $prefs.Top -ne -1)
$window.Left=if ($hasSavedPosition) { [Math]::Max([Windows.SystemParameters]::VirtualScreenLeft,[Math]::Min([double]$prefs.Left,[Windows.SystemParameters]::VirtualScreenLeft+[Windows.SystemParameters]::VirtualScreenWidth-100)) } else { $area.Right-$window.Width-20 }
$window.Top=if ($hasSavedPosition) { [Math]::Max([Windows.SystemParameters]::VirtualScreenTop,[Math]::Min([double]$prefs.Top,[Windows.SystemParameters]::VirtualScreenTop+[Windows.SystemParameters]::VirtualScreenHeight-80)) } else { $area.Top+50 }
$window.Topmost=[bool]$prefs.Topmost; $Pin.IsChecked=[bool]$prefs.Topmost
$window.Content.Background.Opacity=[Math]::Max(0.4,[Math]::Min(1,[double]$prefs.Opacity))
$LiveOpacity.Value=$window.Content.Background.Opacity*100; $LiveOpacityLabel.Text=('{0:N0}%' -f $LiveOpacity.Value)
$opacitySaveTimer=New-Object Windows.Threading.DispatcherTimer
$opacitySaveTimer.Interval=[TimeSpan]::FromMilliseconds(350)
$opacitySaveTimer.Add_Tick({ $opacitySaveTimer.Stop(); Save-Preferences })
$LiveOpacity.Add_ValueChanged({
    $window.Content.Background.Opacity=$LiveOpacity.Value/100; $prefs.Opacity=$window.Content.Background.Opacity
    $LiveOpacityLabel.Text=('{0:N0}%' -f $LiveOpacity.Value)
    $opacitySaveTimer.Stop(); $opacitySaveTimer.Start()
})
function Sync-Pin {
    $Pin.IsChecked=$window.Topmost
    $QuickPin.Content=if ($window.Topmost) { 'Pinned' } else { 'Pin on top' }
}
Sync-Pin
$QuickPin.Add_Click({ $window.Topmost=-not $window.Topmost; $prefs.Topmost=$window.Topmost; Sync-Pin; Save-Preferences })
$cornerMenu=New-Object Windows.Controls.ContextMenu
foreach ($entry in @(@('Top left','TopLeft'),@('Top right','TopRight'),@('Bottom left','BottomLeft'),@('Bottom right','BottomRight'))) {
    $item=New-Object Windows.Controls.MenuItem; $item.Header=$entry[0]; $item.Tag=$entry[1]
    $item.Add_Click({ param($sender,$eventArgs) $prefs.Corner=$sender.Tag; Position-Widget; Save-Preferences })
    [void]$cornerMenu.Items.Add($item)
}
$QuickCorner.ContextMenu=$cornerMenu
$QuickCorner.Add_Click({ $cornerMenu.PlacementTarget=$QuickCorner; $cornerMenu.IsOpen=$true })
function Select-WidgetTask([int]$offset) {
    $chats=@($shared.Latest.Cards)
    if ($chats.Count -lt 2) { return }
    $ids=@($chats | ForEach-Object Id)
    $index=[array]::IndexOf($ids,$script:displayedTask)
    $script:selectedTask=$ids[($index+$offset+$ids.Count)%$ids.Count]
    Update-Cards $shared.Latest
    Update-ParkedBar
}
$PreviousTask.Add_Click({ Select-WidgetTask -1 }); $NextTask.Add_Click({ Select-WidgetTask 1 })
function Get-WidgetWorkArea {
    $handle=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if ($handle -eq [IntPtr]::Zero) { return [Windows.SystemParameters]::WorkArea }
    $rect=[Windows.Forms.Screen]::FromHandle($handle).WorkingArea
    $source=[Windows.Interop.HwndSource]::FromHwnd($handle)
    $transform=$source.CompositionTarget.TransformFromDevice
    $origin=$transform.Transform([Windows.Point]::new($rect.Left,$rect.Top))
    $size=$transform.Transform([Windows.Point]::new($rect.Width,$rect.Height))
    return [Windows.Rect]::new($origin.X,$origin.Y,$size.X,$size.Y)
}
function Position-Widget([switch]$Snap) {
    $workArea=Get-WidgetWorkArea
    $right=[Math]::Max($workArea.Left,$workArea.Right-$window.Width)
    $bottom=[Math]::Max($workArea.Top,$workArea.Bottom-$window.Height)
    if ($Snap) {
        $leftNear=[Math]::Abs($window.Left-$workArea.Left) -lt 48
        $rightNear=[Math]::Abs($window.Left-$right) -lt 48
        $topNear=[Math]::Abs($window.Top-$workArea.Top) -lt 48
        $bottomNear=[Math]::Abs($window.Top-$bottom) -lt 48
        $prefs.Corner='Free'
        if (($leftNear -or $rightNear) -and ($topNear -or $bottomNear)) {
            $prefs.Corner=$(if ($topNear) { 'Top' } else { 'Bottom' })+$(if ($leftNear) { 'Left' } else { 'Right' })
        }
    }
    switch ($prefs.Corner) {
        'TopLeft' { $window.Left=$workArea.Left+12; $window.Top=$workArea.Top+12 }
        'TopRight' { $window.Left=$right-12; $window.Top=$workArea.Top+12 }
        'BottomLeft' { $window.Left=$workArea.Left+12; $window.Top=$bottom-12 }
        'BottomRight' { $window.Left=$right-12; $window.Top=$bottom-12 }
    }
    $window.Left=[Math]::Max($workArea.Left,[Math]::Min($window.Left,$right))
    $window.Top=[Math]::Max($workArea.Top,[Math]::Min($window.Top,$bottom))
    $prefs.Left=$window.Left; $prefs.Top=$window.Top
}
function Set-WidgetCompact([bool]$compact) {
    $SettingsHost.Visibility='Collapsed'
    $window.FindName('AppearanceControls').Visibility='Visible'
    $LimitsMode.Tag=''
    $ContextMode.Tag=if ($prefs.Mode -eq 'Context') {'Selected'} else {''}
    $TokenMode.Tag=if ($prefs.Mode -eq 'Tokens') {'Selected'} else {''}
    if ($compact) {
        $FullPanel.Visibility='Collapsed'; $MiniPanel.Visibility='Visible'; $ResizeGrip.Visibility='Collapsed'
        $window.Width=370; $window.Height=480; $ToggleButton.Content='Expand'
    } else {
        $FullPanel.Visibility='Visible'; $MiniPanel.Visibility='Collapsed'; $ResizeGrip.Visibility='Visible'
        $workArea=Get-WidgetWorkArea
        $window.Width=[Math]::Min($workArea.Width,[Math]::Max(360,[double]$prefs.Width))
        $window.Height=[Math]::Min($workArea.Height,[Math]::Max(520,[double]$prefs.Height)); $ToggleButton.Content='Collapse'
    }
    $prefs.Compact=$compact
    $AuthorLine.Visibility=if ($compact) {'Collapsed'} else {'Visible'}
    $TokensPanel.Visibility='Collapsed'
    if ($prefs.Mode -eq 'Tokens') {
        $MiniPanel.Visibility='Collapsed'; $FullPanel.Visibility='Collapsed'; $TokensPanel.Visibility='Visible'
    }
    Position-Widget
}
function Set-WidgetMode([string]$mode) {
    $prefs.Mode=$mode; $shared.Mode=$mode
    $ContextMode.Tag=if ($mode -eq 'Context') {'Selected'} else {''}
    $TokenMode.Tag=if ($mode -eq 'Tokens') {'Selected'} else {''}
    Set-WidgetCompact ([bool]$prefs.Compact); Save-Preferences
}
$ContextMode.Add_Click({ Set-WidgetMode 'Context' })
$TokenMode.Add_Click({ Set-WidgetMode 'Tokens' })
$LimitsMode.Add_Click({ Show-Settings 'Context' })
$RefreshUsage.Add_Click({ if (-not $shared.Fetching) { $shared.RefreshQuota=$true } })
$UserWebsite.Add_RequestNavigate({ param($sender,$eventArgs)
    $launch=New-Object Diagnostics.ProcessStartInfo('https://yahyanabil.com'); $launch.UseShellExecute=$true
    [void][Diagnostics.Process]::Start($launch); $eventArgs.Handled=$true
})
$script:contextQuotaRows=@{}
function Update-ContextQuotaBars {
    $quota=Select-FreshQuota $shared.LiveQuota $shared.Latest.Tokens.Quota
    $entries=if ($quota) {@($quota.Windows)} else {@()}
    if(-not $entries.Count){$entries=@([pscustomobject]@{Name='5h';Minutes=300;Remaining=$null},[pscustomobject]@{Name='7d';Minutes=10080;Remaining=$null})}
    $RefreshUsage.Content=if($shared.Fetching){'...'}else{[char]0xE72C}
    $RefreshUsage.FontFamily=if($shared.Fetching){'Segoe UI'}else{'Segoe MDL2 Assets'}
    $RefreshUsage.IsEnabled=-not $shared.Fetching
    $RefreshUsage.ToolTip=if($shared.QuotaError){$shared.QuotaError}else{'Refresh account quotas. The bars show the remaining quota. Move the pointer over a bar for details.'}
    $keys=@()
    foreach ($entry in $entries) {
        $key=$entry.Name; $keys+=$key
        if (-not $script:contextQuotaRows.ContainsKey($key)) {
            $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='0,0,10,4'
            $label=New-Label '' 10
            $bar=New-Object Windows.Controls.ProgressBar; $bar.Height=5; $bar.Maximum=100; $bar.Margin='0,3,0,0'
            [void]$panel.Children.Add($label); [void]$panel.Children.Add($bar)
            Apply-WidgetTheme $panel; [void]$ContextQuotaBars.Children.Add($panel)
            $script:contextQuotaRows[$key]=@{Panel=$panel;Label=$label;Bar=$bar}
        }
        $row=$script:contextQuotaRows[$key]
        $period=if ($entry.Minutes -eq 300) {'5h'} elseif ($entry.Minutes -eq 10080) {'7d'} else {$entry.Name}
        if($null -eq $entry.Remaining){$row.Label.Text="$period | --";$row.Bar.Value=0;$row.Panel.ToolTip='No account quota reading is available.';continue}
        $observed=if ($entry.Observed) {$entry.Observed} else {$quota.Observed}; $stale=([DateTimeOffset]::Now-$observed).TotalMinutes -gt 2
        $row.Label.Text=('{0} | {1:N0}% left{2}' -f $period,$entry.Remaining,$(if($stale){' *'}else{''}))
        $row.Bar.Value=$entry.Remaining
        $row.Panel.ToolTip="$($entry.Name) | $($quota.Plan)`n$('{0:N0}% used' -f (100-$entry.Remaining))`n$(Format-QuotaReset $entry.Reset)`nObserved $($observed.ToLocalTime().ToString('MMM d HH:mm:ss'))$(if($stale){' (older reading)'})`n$($quota.Source)"
    }
    foreach ($key in @($script:contextQuotaRows.Keys)) {
        if ($key -notin $keys) { [void]$ContextQuotaBars.Children.Remove($script:contextQuotaRows[$key].Panel); $script:contextQuotaRows.Remove($key) }
    }
}
$script:tokenMetricRows=@{}; $script:tokenTaskRows=@{}
function New-TokenDetailPanel {
    $panel=New-Object Windows.Controls.StackPanel
    $grid=New-Object Windows.Controls.Primitives.UniformGrid; $grid.Columns=2
    $values=@{}
    foreach($name in @('Input','Output','Cached input','Uncached input','Reasoning','Other output')) {
        $tile=New-Object Windows.Controls.Border; $tile.Background='#1B263B';$tile.CornerRadius=6;$tile.Padding=8;$tile.Margin='0,0,5,5'
        $body=New-Object Windows.Controls.StackPanel
        [void]$body.Children.Add((New-Label $name 10 '#778DA9'))
        $value=New-Label '--' 18;$values[$name]=$value;[void]$body.Children.Add($value)
        $tile.Child=$body;[void]$grid.Children.Add($tile)
    }
    [void]$panel.Children.Add($grid)
    $ratios=New-Label '' 10 '#778DA9';[void]$panel.Children.Add($ratios)
    $latest=New-Label '' 10
    $last=New-Object Windows.Controls.Expander;$last.Header='Latest request';$last.Content=$latest;[void]$panel.Children.Add($last)
    $tools=New-Label '' 11
    $activity=New-Object Windows.Controls.Expander;$activity.Header='Tool calls';$activity.Content=$tools;$activity.Margin='0,5,0,0';[void]$panel.Children.Add($activity)
    $data=New-Label '' 10 '#778DA9'
    $help=New-Object Windows.Controls.Expander;$help.Header='Data and estimate';$help.Content=$data;$help.Margin='0,5,0,0';[void]$panel.Children.Add($help)
    return @{Panel=$panel;Values=$values;Ratios=$ratios;Latest=$latest;Tools=$tools;Activity=$activity;Data=$data}
}
function Update-TokenDetailPanel($view,$chat) {
    $other=if($null -ne $chat.Output -and $null -ne $chat.Reasoning -and $chat.Reasoning -le $chat.Output){$chat.Output-$chat.Reasoning}else{$null}
    $map=@{Input=$chat.Input;Output=$chat.Output;'Cached input'=$chat.Cached;'Uncached input'=$chat.Uncached;Reasoning=$chat.Reasoning;'Other output'=$other}
    foreach($key in $map.Keys){$view.Values[$key].Text=Format-ShortTokenValue $map[$key];$view.Values[$key].ToolTip="$(Format-TokenValue $map[$key]) tokens"}
    $hit=if($chat.Input -gt 0 -and $null -ne $chat.Cached -and $chat.Cached -le $chat.Input){'{0:N1}%' -f (100.0*$chat.Cached/$chat.Input)}else{'--'}
    $share=if($chat.Output -gt 0 -and $null -ne $chat.Reasoning -and $chat.Reasoning -le $chat.Output){'{0:N1}%' -f (100.0*$chat.Reasoning/$chat.Output)}else{'--'}
    $view.Ratios.Text="Cache hit: $hit   |   Reasoning share: $share"
    $view.Latest.Text="Input: $(Format-TokenValue $chat.LastInput)`nCached input: $(Format-TokenValue $chat.LastCached)`nOutput: $(Format-TokenValue $chat.LastOutput)"
    $a=$chat.Activity
    $view.Activity.Header=if($a.Ready){"Tool calls: $(Format-TokenValue $a.Calls)$(if($a.Partial){' *'})"}else{'Tool calls: --'}
    $lines=@()
    if($a.Ready){
        $top=@($a.Tools|Select-Object -First 6)
        foreach($tool in $top){$lines+="$($tool.Name)   $(Format-TokenValue $tool.Count)"}
        if(@($a.Tools).Count -gt 6){$rest=($a.Tools|Select-Object -Skip 6|Measure-Object Count -Sum).Sum;$lines+="Other calls   $(Format-TokenValue $rest)"}
        if(-not $top.Count){$lines+='No tool calls are in this record.'}
    }else{$lines+='No complete call record is available.'}
    if($a.Partial){$lines+='* Some calls lack an ID or exceed the scan limit.'}
    $lines+='Call counts cover this rollout record. They do not measure token cost.'
    $lines+='Tool tokens: --. Automation tokens: --. Codex supplies no separate counters.'
    $view.Tools.Text=$lines -join "`n"
    $view.Data.Text="Last model: $($chat.Model)`nLast record: $(if($chat.Observed){$chat.Observed.ToLocalTime().ToString('MMM d HH:mm:ss')}else{'--'})`nClient: $(if($a.Originator){$a.Originator}else{'--'})`nTotals include earlier models. Cache is part of input. Reasoning is part of output.`n$($chat.QuotaNotes)`nQuota shares are estimates. pp means percentage points of account allowance."
}
function Update-TokenPanel($tokens=$shared.Latest.Tokens) {
    $TokenLive.Text=if ($shared.Error) {'Read error'} else {'File check | 1 s'}
    $TokenLive.ToolTip=if ($shared.Error) {$shared.Error} else {'CTC reads local usage records each second. Codex can write usage after a request ends.'}
    if ($tokens -and $tokens.Tasks) {
        $TokenTotal.Text=Format-TokenValue $tokens.Total
        $age=[Math]::Max(0,[int]([DateTimeOffset]::Now-$tokens.Observed).TotalSeconds)
        $TokenBreakdown.Text="$($tokens.Tasks) chats | Last record $($tokens.Observed.ToLocalTime().ToString('HH:mm:ss'))"
        if ($age -gt 120) { $TokenBreakdown.Text+=' | No recent usage record' }
        $TokenCoverage.Text="Total = input + output.`nInput includes cached input. Output includes reasoning.`n-- means no value. * means incomplete data.`n$($tokens.Coverage)`nQuotas apply to the account. Token counts come from this device."
    } else { $TokenTotal.Text='--'; $TokenBreakdown.Text='Waiting for a usage record'; $TokenCoverage.Text='Counts appear when Codex writes a usage record. CTC does not add estimated tokens between records.' }
    $metricDefs=@(
        @('Input','Input','DetailedTasks','Input includes cached input.'),
        @('Output','Output','DetailedTasks','Output includes reasoning.'),
        @('Cache','Cached','CacheTasks','These input tokens come from cache. Input includes these tokens.'),
        @('Uncached','Uncached','CacheTasks','Uncached input equals input minus cached input.'),
        @('Reasoning','Reasoning','ReasoningTasks','Output includes reasoning tokens.'),
        @('Cache hit','Hit','CacheTasks','Cache hit equals cached input divided by input. Both values must be available.')
    )
    foreach ($def in $metricDefs) {
        $key=$def[1]
        if (-not $script:tokenMetricRows.ContainsKey($key)) {
            $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='0,0,8,4'; $panel.ToolTip=$def[3]
            $label=New-Label $def[0] 10 '#778DA9'; $value=New-Label '--' 17 '#E0E1DD'
            [void]$panel.Children.Add($label); [void]$panel.Children.Add($value); [void]$TokenMetrics.Children.Add($panel)
            $script:tokenMetricRows[$key]=$value
        }
        $count=if ($tokens) {$tokens.($def[2])} else {0}
        $value='--'
        if ($count -gt 0) {
            $value=if ($key -eq 'Hit') { if (($tokens.Cached+$tokens.Uncached) -gt 0) { '{0:N1}%' -f (100.0*$tokens.Cached/($tokens.Cached+$tokens.Uncached)) } else {'--'} } else { Format-TokenValue $tokens.$key }
            if ($count -lt $tokens.Tasks) { $value+=' *' }
        }
        $script:tokenMetricRows[$key].Text=$value
        $script:tokenMetricRows[$key].ToolTip="$count of $($tokens.Tasks) chats have this detail. $($def[3])"
    }
    $hasActive=@($tokens.ActiveRows|Where-Object {$_}).Count -gt 0
    $ActiveTokenHeading.Visibility=if ($hasActive) {'Visible'} else {'Collapsed'}
    if ($script:previousActiveTokenState -ne $hasActive) { $TokenSummary.IsExpanded=-not $hasActive; $script:previousActiveTokenState=$hasActive }
    $keys=@()
    foreach ($chat in @($tokens.Rows)) {
        if (-not $chat) { continue }; $key=$chat.Id; $keys+=$key
        if (-not $script:tokenTaskRows.ContainsKey($key)) {
            $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='0,3,0,9'
            $title=New-Label '' 13 '#778DA9'; $detail=New-TokenDetailPanel; $total=New-Label '' 25 '#E0E1DD'
            $brief=New-Label '' 11 '#778DA9'
            $expand=New-Object Windows.Controls.Expander; $expand.Header='Breakdown'; $expand.Content=$detail.Panel; $expand.Margin='0,5,0,0'
            [void]$panel.Children.Add($title); [void]$panel.Children.Add($total); [void]$panel.Children.Add($brief); [void]$panel.Children.Add($expand); [void]$TokenTasks.Children.Add($panel)
            $script:tokenTaskRows[$key]=@{Panel=$panel;Title=$title;Total=$total;Detail=$detail;Brief=$brief;Expand=$expand}
        }
        $row=$script:tokenTaskRows[$key]
        $target=if ($chat.Active) {$ActiveTokenTasks} else {$TokenTasks}
        if ($row.Panel.Parent -ne $target) { [void]$row.Panel.Parent.Children.Remove($row.Panel); [void]$target.Children.Add($row.Panel) }
        $row.Total.Text="$(Format-TokenValue $chat.Total) tokens"
        $row.Total.ToolTip='These counts include previous requests in this chat.'
        $status=if ($chat.Active) {'Running'} else {'Idle'}
        $row.Title.Text="$($chat.Title) | $status"
        $row.Brief.Text=if($chat.QuotaShare){$chat.QuotaShare}else{'Quota estimate: 5h -- | 7d --'}
        $row.Brief.ToolTip=$chat.QuotaNotes
        Update-TokenDetailPanel $row.Detail $chat
        $row.Title.ToolTip=$chat.Title; $row.Panel.ToolTip=$null
    }
    foreach ($key in @($script:tokenTaskRows.Keys)) { if ($key -notin $keys) { [void]$script:tokenTaskRows[$key].Panel.Parent.Children.Remove($script:tokenTaskRows[$key].Panel); $script:tokenTaskRows.Remove($key) } }
    $quota=Select-FreshQuota $shared.LiveQuota $tokens.Quota
    $entries=@(); if ($quota) { $entries=@($quota.Windows) }
    $TokenSource.Text=if ($quota) { "$($quota.Source) | $($quota.Plan) | checked $($quota.Observed.ToLocalTime().ToString('MMM d HH:mm:ss'))" } else { 'No quota reading is available. Sign in to Codex.' }
    if ($quota -and -not $entries.Count) { $TokenSource.Text+=' | Codex supplied no quota windows.' }
    if ($quota -and $null -ne $quota.ResetCredits) { $TokenSource.Text+="`nAvailable reset credits: $($quota.ResetCredits) (read only)" }
    if ($shared.Fetching) { $TokenSource.Text+=' | Refreshing...' }
    elseif ($shared.QuotaError) { $TokenSource.Text+="`n$($shared.QuotaError)" }
    if ($quota -and ([DateTimeOffset]::Now-$quota.Observed).TotalMinutes -gt 2) { $TokenSource.Text+=' | Old data' }

}
$window.Add_SourceInitialized({ Set-WidgetCompact ([bool]$prefs.Compact) })
$DragHandle.Add_MouseLeftButtonDown({
    param($sender,$eventArgs)
    $source=$eventArgs.OriginalSource
    while ($source -and $source -ne $DragHandle) {
        if ($source -is [Windows.Controls.Primitives.ButtonBase]) { return }
        $source=[Windows.Media.VisualTreeHelper]::GetParent($source)
    }
    $window.DragMove(); Position-Widget -Snap; Save-Preferences
})
$ResizeGrip.Add_DragDelta({
    param($sender,$eventArgs)
    $workArea=Get-WidgetWorkArea
    $window.Width=[Math]::Max(360,[Math]::Min($workArea.Width,$window.Width+$eventArgs.HorizontalChange))
    $window.Height=[Math]::Max(520,[Math]::Min($workArea.Height,$window.Height+$eventArgs.VerticalChange))
    $prefs.Width=$window.Width; $prefs.Height=$window.Height
})
$ResizeGrip.Add_DragCompleted({ Position-Widget; Save-Preferences })
$ToggleButton.Add_Click({
    $editing=($SettingsHost.Visibility -eq 'Visible' -and $script:settings -and $script:settings.dialog.FindName('ContextSettings').Visibility -eq 'Visible')
    Set-WidgetCompact (-not [bool]$prefs.Compact)
    if ($editing) { Show-LimitEditorSurface }
    Save-Preferences
})
$MiniEditContext.Add_Click({
    $id=$script:displayedTask
    if (-not $id) { return }
    $card=@($script:shared.Latest.Cards | Where-Object Id -eq $id)[0]
    if (-not $card.Cwd) { return }
    Show-Settings 'Context'
    foreach ($choice in $script:settings.scope.Items) {
        if ($choice.Path -eq (Join-Path $card.Cwd '.codex/config.toml')) { $choice.Card=$card; $script:settings.scope.SelectedItem=$choice; break }
    }

})
$MiniTitle.Add_MouseLeftButtonUp({ Set-WidgetCompact $false; Save-Preferences })
$MinimizeButton.Add_Click({ $window.WindowState='Minimized' })
$CloseButton.Add_Click({ $window.Close() })
$script:cardControls=@{}
function New-Label([string]$text,[int]$size=12,[string]$color='#E0E1DD') {
    $label=New-Object Windows.Controls.TextBlock
    $label.Text=$text; $label.FontSize=$size; $label.Foreground=$color
    $label.TextWrapping='Wrap'; $label.Margin='0,3,0,3'; return $label
}
function Update-Cards($snapshot) {
    $active=@($snapshot.Cards)
    if ($active.Count) {
        $lead=$active[0]
        if ($script:selectedTask) { $chosen=@($active | Where-Object Id -eq $script:selectedTask); if ($chosen.Count) { $lead=$chosen[0] } }
        $script:displayedTask=$lead.Id; $MiniEditContext.IsEnabled=[bool]$lead.Cwd
        $MiniTitle.Text=$lead.Title; $MiniTitle.ToolTip=$lead.Title
        $MiniStatus.Text="$($active.Count) active | $($lead.Status) | $($lead.Model)"
        if ($lead.Percent -ge 95) { $MiniStatus.Text+=' | CRITICAL' } elseif ($lead.Percent -ge 80) { $MiniStatus.Text+=' | HIGH' }
        $MiniUsage.Text=if ($null -ne $lead.Percent) { '{0:N0} / {1:N0} tokens' -f $lead.Input,$lead.Window } else { 'No usage record' }
        $MiniPercent.Text=if ($null -ne $lead.Percent) { '{0:N1}%' -f $lead.Percent } else { '--' }
        $MiniRemaining.Text=if ($null -ne $lead.Input -and $lead.Window -gt 0) { '{0:N0}' -f [Math]::Max(0,$lead.Window-$lead.Input) } else { '--' }
        $MiniCompactions.Text=[string]$lead.Compactions
        $MiniCached.Text=if ($lead.Input -gt 0) { '{0:N0}%' -f (100*$lead.Cached/$lead.Input) } else { '--' }
        $MiniUpdated.Text=if ($lead.Saved.Status -eq 'Pending') {'Saved - waiting for reload'} else {"Last event $($lead.LastEvent)"}
        $MiniUpdated.ToolTip=if ($lead.Saved) {$lead.Saved.Message} else {$null}
        $TaskPosition.Text=('{0} / {1}' -f (1+[array]::IndexOf($active,$lead)),$active.Count)
        $MiniBar.Value=[Math]::Max(0,[Math]::Min(100,[double]$lead.Percent))
        $MiniBar.Foreground=if ($lead.Status -eq 'COMPACTING') { '#778DA9' } elseif ($lead.Percent -ge 95) { '#778DA9' } elseif ($lead.Percent -ge 80) { '#778DA9' } else { '#778DA9' }
        $MiniPercent.Foreground=$MiniBar.Foreground
    } else {
        $MiniEditContext.IsEnabled=$false; $MiniTitle.Text='No running chats'; $MiniTitle.ToolTip=$null
        $MiniStatus.Text='No active chats'; $MiniBar.Value=0
        $MiniUsage.Text='No usage record'; $MiniPercent.Text='--'
        $MiniRemaining.Text='--'; $MiniCompactions.Text='--'; $MiniCached.Text='--'
        $MiniUpdated.Text='Monitoring local chats'; $TaskPosition.Text='0 / 0'
    }
    $PreviousTask.IsEnabled=($active.Count -gt 1); $NextTask.IsEnabled=$PreviousTask.IsEnabled
    $ids=@($snapshot.Cards | ForEach-Object { $_.Id })
    foreach ($id in @($script:cardControls.Keys)) {
        if ($id -notin $ids) { if($script:cardControls[$id].Editor.Tag.RestartView){[void]$script:restartControls.Remove($script:cardControls[$id].Editor.Tag.RestartView)}; [void]$Cards.Children.Remove($script:cardControls[$id].Border); $script:cardControls.Remove($id) }
    }
    if ($script:emptyLabel) { [void]$Cards.Children.Remove($script:emptyLabel); $script:emptyLabel=$null }
    if ($ids.Count -eq 0) {
        $script:emptyLabel=New-Label 'No active chats.' 17 '#E0E1DD'
        [void]$Cards.Children.Add($script:emptyLabel)
    }
    $position=0
    foreach ($card in $snapshot.Cards) {
        if (-not $script:cardControls.ContainsKey($card.Id)) {
            $border=New-Object Windows.Controls.Border
            $border.Background='#1B263B'; $border.CornerRadius='10'; $border.Padding='14'; $border.Margin='0,0,0,10'
            $panel=New-Object Windows.Controls.StackPanel; $border.Child=$panel
            $controls=@{ Border=$border }
            foreach ($item in @('Status','Title','Model','Usage')) {
                $label=New-Label ''
                if ($item -eq 'Title') { $label.FontSize=17; $label.FontWeight='SemiBold' }
                $controls[$item]=$label; [void]$panel.Children.Add($label)
            }
            $bar=New-Object Windows.Controls.ProgressBar; $bar.Height=7; $bar.Maximum=100; $bar.Margin='0,7,0,7'; $bar.Background='#415A77'
            $controls.Bar=$bar; [void]$panel.Children.Add($bar)
            $detailsPanel=New-Object Windows.Controls.StackPanel
            $detailsExpander=New-Object Windows.Controls.Expander; $detailsExpander.Header='Details'; $detailsExpander.Content=$detailsPanel
            foreach ($item in @('Saved','Details')) { $label=New-Label ''; $label.FontSize=11; $controls[$item]=$label; [void]$detailsPanel.Children.Add($label) }
            [void]$panel.Children.Add($detailsExpander); Apply-WidgetTheme $detailsExpander
            if ($card.Cwd) {
                $editor=New-InlineLimitsEditor $card.Cwd $card; $controls.Editor=$editor
                [void]$panel.Children.Add($editor)
            }
            $script:cardControls[$card.Id]=$controls; [void]$Cards.Children.Add($border)
        }
        $c=$script:cardControls[$card.Id]
        if ($Cards.Children.IndexOf($c.Border) -ne $position) { [void]$Cards.Children.Remove($c.Border); $Cards.Children.Insert($position,$c.Border) }
        $position++
        $color=if ($card.Status -eq 'COMPACTING') { '#778DA9' } elseif ($card.Status -ne 'RUNNING' -or $card.Percent -ge 80) { '#778DA9' } else { '#778DA9' }
        if ($card.Percent -ge 95 -or $card.Error) { $color='#778DA9' }
        $c.Status.Text=$card.Status
        if ($card.Percent -ge 95) { $c.Status.Text+=' / CRITICAL CONTEXT' } elseif ($card.Percent -ge 80) { $c.Status.Text+=' / HIGH CONTEXT' }
        $c.Status.Foreground=$color; $c.Title.Text=$card.Title
        $c.Title.ToolTip="Initial: $($card.Initial)`nChat: $($card.Id)"
        $c.Model.Text="$($card.Model)"; $c.Model.ToolTip=$card.Cwd
        $c.Usage.Text=if ($null -ne $card.Percent) { '{0:N1}%   {1:N0} / {2:N0} tokens' -f $card.Percent,$card.Input,$card.Window } else { 'No token usage record' }
        $c.Bar.Value=[Math]::Min(100,[Math]::Max(0,[double]$card.Percent)); $c.Bar.Foreground=$color
        $c.Saved.Text=''
        if ($card.Saved) {
            if ($card.Saved.Error) { $c.Saved.Text=$card.Saved.Error }
            else {
                $c.Saved.Text='Saved {0}: {1:N0} tokens' -f $card.Saved.Source,$card.Saved.Requested
                if ($null -ne $card.Saved.Expected) {
                    $c.Saved.Text+=' -> {0:N0} usable' -f $card.Saved.Expected
                    $c.Saved.Text+=if ($card.Saved.Expected -eq $card.Window) { ' (confirmed in this chat)' } else { ' (waiting for reload)' }
                } else { $c.Saved.Text+=' (chat window unknown)' }
            }
        }
        $c.Saved.ToolTip=$card.Saved.Message
        $c.Saved.Foreground='#778DA9'
        $c.Details.Text="Compactions: $($card.Compactions)  |  Last event: $($card.LastEvent)`nCached input: $('{0:N0}' -f $card.Cached)  |  Output: $('{0:N0}' -f $card.Output)"
        if ($card.Error) { $c.Details.Text+="`nRead error: $($card.Error)" }
    }
}
function Update-ParkedBar {
    if(-not $script:restoreTab){return}
    $snapshot=$shared.Latest;$chats=@($snapshot.Cards)
    $chat=@($chats|Where-Object Id -eq $script:displayedTask|Select-Object -First 1)
    $lead=if($chat.Count){$chat[0]}elseif($chats.Count){$chats[0]}else{$null}
    $script:parkTitle.Text=if($lead){$lead.Title}else{'No active chats'};$script:parkTitle.ToolTip=$script:parkTitle.Text
    $script:parkContext.Text=if($lead -and $null -ne $lead.Percent){'Context {0:N1}%' -f $lead.Percent}else{'Context --'}
    $script:parkContext.ToolTip=if($lead){"$(Format-TokenValue $lead.Input) / $(Format-TokenValue $lead.Window) tokens"}else{$null}
    $tokens=@($snapshot.Tokens.Rows|Where-Object Id -eq $lead.Id|Select-Object -First 1)
    $total=if($tokens.Count){$tokens[0].Total}else{$null}
    $script:parkTokens.Text="Tokens $(Format-ShortTokenValue $total)";$script:parkTokens.ToolTip="$(Format-TokenValue $total) tokens"
    $quota=Select-FreshQuota $shared.LiveQuota $snapshot.Tokens.Quota
    $parts=@()
    foreach($minutes in @(300,10080)){
        $entries=@($quota.Windows|Where-Object Minutes -eq $minutes)
        $value=if($entries.Count -eq 1){'{0:N0}%' -f $entries[0].Remaining}else{'--'}
        $name=if($minutes -eq 300){'5h'}else{'7d'};$parts+="$name $value left"
    }
    $script:parkQuota.Text=$parts -join '  |  '
    $script:parkQuota.ToolTip=if($quota){"Quota checked: $($quota.Observed.ToLocalTime().ToString('HH:mm:ss'))"}else{'No quota reading is available.'}
    $script:parkPrevious.IsEnabled=($chats.Count -gt 1);$script:parkNext.IsEnabled=$script:parkPrevious.IsEnabled
}
function Show-Overlay {
    if ($script:restoreTab) { $script:restoreTab.Hide() }
    $window.Show(); $window.WindowState='Normal'; [void]$window.Activate()
}
function Hide-Overlay([bool]$park=$false) {
    if ($park) {
        $workArea=Get-WidgetWorkArea
        $corner=$prefs.Corner
        if($corner -eq 'Free'){
            $horizontal=if($window.Left+$window.Width/2 -lt $workArea.Left+$workArea.Width/2){'Left'}else{'Right'}
            $vertical=if($window.Top+$window.Height/2 -lt $workArea.Top+$workArea.Height/2){'Top'}else{'Bottom'}
            $corner=$vertical+$horizontal
        }
        $script:restoreTab.Width=[Math]::Min(370,[Math]::Max(220,$workArea.Width-24))
        $script:restoreTab.Left=if($corner.EndsWith('Left')){$workArea.Left+12}else{$workArea.Right-$script:restoreTab.Width-12}
        $script:restoreTab.Top=if($corner.StartsWith('Top')){$workArea.Top+12}else{$workArea.Bottom-$script:restoreTab.Height-12}
        $script:restoreTab.Opacity=$window.Opacity;$script:restoreTab.Topmost=$window.Topmost
        Update-ParkedBar
        $script:restoreTab.Show()
    } else {
        $script:restoreTab.Hide()
        $tray.ShowBalloonTip(4000,'Context-Token Codex is running','To restore the widget, select the ctc icon beside the clock. Check the ^ menu if necessary.',[Windows.Forms.ToolTipIcon]::Info)
    }
    $window.Hide()
}
function Update-CompactPercentageHint($form) {
    if ($form.Loading) { return }
    $form.Result.Text=''; $form.Result.Tag=''
    try {
        $draft=ConvertTo-ContextDraft $form.Window.Text $form.Compact.Text
        $changed=($draft.Window -ne $form.Baseline.SavedWindow -or $draft.Compact -ne $form.Baseline.SavedCompact)
        $status=if ($changed) {'Select Save to store these values.'} else {'These values are saved.'}
        $form.Hint.Text=if ($null -ne $draft.Window -and $null -ne $draft.Compact) {
            ('{0:N1}% = {1:N0} tokens. ' -f (100.0*$draft.Compact/$draft.Window),$draft.Compact)+$status
        } else { 'Example: 90% of 200k = 180k. CTC saves the percentage as tokens.' }
        if ($form.Baseline -and $form.Baseline.Maximum -gt 0 -and $draft.Window -gt $form.Baseline.Maximum) {
            $form.Result.Tag='Warning'; $form.Result.Text=('Model catalog limit: {0:N0} ({1}). This value is larger. Codex can reject or reduce it.' -f $form.Baseline.Maximum,$form.Baseline.Model)
        }
        $form.Save.IsEnabled=$changed
        $form.Window.BorderBrush='#415A77'; $form.Compact.BorderBrush='#415A77'
    } catch {
        $form.Hint.Text=$_.Exception.Message; $form.Result.Text=$_.Exception.Message; $form.Result.Tag='Error'; $form.Save.IsEnabled=$false
        $form.Window.BorderBrush='#778DA9'; $form.Compact.BorderBrush='#778DA9'
    }
    foreach ($button in $form.ScaleButtons) {
        $button.IsEnabled=($form.Baseline.Base -gt 0)
        $button.ToolTip=if ($button.IsEnabled) { '{0:N0} tokens. Uses the displayed base value. Repeated selections do not multiply the previous result. Select Save to store the values.' -f ([decimal]$form.Baseline.Base*$button.Tag.Multiplier) } else { 'Enter a number for the context window first.' }
    }
}
function Set-LimitFormScope($form,[string]$path,$card) {
    $form.Path=$path; $form.Card=$card; $form.Loading=$true
    try {
        $form.Baseline=Get-LimitEditorBaseline $path $card
        $b=$form.Baseline
        $form.Window.Text=if ($null -eq $b.SavedWindow) {'default'} else {[string]$b.SavedWindow}
        $form.Compact.Text=if ($null -eq $b.SavedCompact) {'default'} else {[string]$b.SavedCompact}
        $form.Current.Text="Saved: $(Format-Limit $b.SavedWindow) | Compact: $(Format-Limit $b.SavedCompact)"
        if ($b.Live -gt 0) { $form.Current.Text+="`nLive: $(Format-Limit $b.Live) | $($b.Model)" }
        $form.Current.ToolTip="File: $path`nApplies to all models in this scope.`nModel catalog limit: $(Format-Limit $b.Maximum)"
        $scope=Get-TopLevelAutoCompactScope $path
        if (-not $scope) { $scope=Get-TopLevelAutoCompactScope $script:configPath }
        if (-not $scope) { $scope='total (default)' }
        $form.Current.ToolTip+="`nCompaction token rule: $scope`nGlobal fallback window: $(Format-Limit (Get-TopLevelContextWindow $script:configPath))`nGlobal fallback Compact at: $(Format-Limit (Get-TopLevelAutoCompactLimit $script:configPath))"
        $form.BaseLabel.Text=if ($b.Base -gt 0) { 'Base: {0:N0} ({1})' -f $b.Base,$b.Source } else { 'No base value is available. Enter a context window.' }
        foreach ($button in $form.ScaleButtons) {
            $button.ToolTip=if ($b.Base -gt 0) { '{0:N0} tokens. Uses the displayed base value. Select Save to store the values.' -f ([decimal]$b.Base*$button.Tag.Multiplier) } else { 'Enter a number for the context window first.' }
        }
    } finally { $form.Loading=$false }
    Update-CompactPercentageHint $form
}
$script:restartControls=New-Object 'Collections.Generic.List[object]'
$script:restartStatusPath=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor/restart.json'
if($TestSeconds -gt 0){$script:restartStatusPath=Join-Path $CodexHome 'restart-test.json'}
function Get-WidgetRestartStatus {
    if(-not [IO.File]::Exists($script:restartStatusPath)){return $null}
    try{return ([IO.File]::ReadAllText($script:restartStatusPath)|ConvertFrom-Json)}catch{return $null}
}
function Start-WidgetRestart([bool]$now) {
    if($TestSeconds -gt 0){return}
    $homePath=if($CodexHome){$CodexHome}elseif($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'}
    $scriptPath=Join-Path $script:folder 'Restart-Codex.ps1'
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$scriptPath+'"'),'-CodexHome',('"'+$homePath+'"'),'-StatusPath',('"'+$script:restartStatusPath+'"'))
    if($now){$arguments+='-Now'}
    Write-RestartStatus $script:restartStatusPath 'Waiting' 'CTC waits for running chats to stop.'
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList $arguments
    Update-LimitRestartControls
}
function Add-LimitRestartControls($parent) {
    $panel=New-Object Windows.Controls.Expander;$panel.Margin='0,8,0,0';$panel.FontSize=10
    $label=$panel
    $row=New-Object Windows.Controls.WrapPanel
    $now=New-Object Windows.Controls.Button;$now.Content='Restart now safely';$now.Padding='7,4';$now.Margin='0,0,5,5'
    $after=New-Object Windows.Controls.Button;$after.Content='Restart after all chats stop';$after.Padding='7,4';$after.Margin='0,0,0,5'
    $cancel=New-Object Windows.Controls.Button;$cancel.Content='Cancel restart';$cancel.Padding='7,4';$cancel.Margin='0,0,0,5'
    $now.ToolTip='CTC checks local chat records. It requests a normal close after the chats are idle. Open windows will close.'
    $after.ToolTip='Queue one restart. CTC waits for recorded chats to stop. Unknown records block the restart. The request expires after 24 h.'
    $now.Add_Click({Start-WidgetRestart $true});$after.Add_Click({Start-WidgetRestart $false})
    $cancel.Add_Click({Write-RestartStatus $script:restartStatusPath 'Cancelled' 'The restart request was cancelled.';Update-LimitRestartControls})
    foreach($button in @($now,$after,$cancel)){[void]$row.Children.Add($button)}
    $panel.Content=$row;[void]$parent.Children.Add($panel)
    $view=@{Label=$label;Now=$now;After=$after;Cancel=$cancel}
    [void]$script:restartControls.Add($view)
    Update-LimitRestartControls
    return $view
}
function Update-LimitRestartControls {
    $state=Get-WidgetRestartStatus
    if($state.Status -eq 'Reopened'){$script:pendingLimits=$false}
    $waiting=$state.Status -in @('Waiting','Closing')
    $pending=@($shared.Latest.Cards|Where-Object {$_.Saved.Status -eq 'Pending'}).Count
    $dirty=$script:pendingLimits -or $state.Status -in @('Saved','Blocked','Expired')
    $gate=$shared.Latest.Restart
    foreach($view in $script:restartControls){
        $view.Label.Header=if($waiting){'Limits updates in queue - waiting for idle chats'}elseif($pending -or $dirty){'Limits updates in queue'}elseif($state.Status -eq 'Reopened'){'Codex reopened - check the next context record'}else{'No limits updates in queue'}
        $view.Label.ToolTip=if($state.Message){$state.Message}else{'Saved values need a fresh Codex session. CTC confirms context values from usage records.'}
        $view.Now.IsEnabled=[bool]$gate.Ready -and -not $waiting
        $view.After.IsEnabled=-not $waiting
        $view.Cancel.Visibility=if($state.Status -eq 'Waiting'){'Visible'}else{'Collapsed'}
    }
}
function Connect-LimitEditor($windowField,$compactField,$hint,$current,$quick,$compactQuick,$resetRow,$save,$result) {
    $form=@{Window=$windowField;Compact=$compactField;Hint=$hint;Current=$current;Save=$save;Result=$result;Loading=$true;Baseline=$null;ScaleButtons=@()}
    $baseLabel=New-Label '' 10; $baseLabel.Margin='0,3,0,3'; $form.BaseLabel=$baseLabel; $form.ResetRow=$resetRow
    [void]$quick.Children.Add($baseLabel)
    $row=New-Object Windows.Controls.WrapPanel; $quick.Children.Insert(0,$row)
    foreach ($factor in @(1,2,3)) {
        $button=New-Object Windows.Controls.Button; $button.Content=([string][char]0xD7)+$factor; $button.Padding='8,3'; $button.Margin='0,0,5,4'
        $button.Tag=@{Form=$form;Multiplier=$factor}; $form.ScaleButtons+=,$button
        $button.Add_Click({param($sender,$eventArgs)
            $f=$sender.Tag.Form
            try {
                $base=$f.Baseline.Base
                if (-not $base) { $base=(ConvertTo-TokenLimit $f.Window.Text $null).Limit }
                $draft=Get-ScaledContextDraft $base $sender.Tag.Multiplier $f.Window.Text $f.Compact.Text
                $f.Loading=$true; $f.Window.Text=$draft.Window; $f.Compact.Text=$draft.Compact; $f.Loading=$false
                Update-CompactPercentageHint $f
            } catch { $f.Loading=$false; $f.Result.Tag='Error'; $f.Result.Text=$_.Exception.Message }
        }); [void]$row.Children.Add($button)
    }
    foreach ($percent in @(80,90,95)) {
        $button=New-Object Windows.Controls.Button; $button.Content="$percent%"; $button.Padding='7,3'; $button.Margin='0,0,6,4'; $button.ToolTip='Set Compact at to this percentage of the entered window. Select Save to store the values.'
        $button.Tag=@{Form=$form;Percent=$percent}
        $button.Add_Click({param($sender,$eventArgs) $sender.Tag.Form.Compact.Text="$($sender.Tag.Percent)%"})
        [void]$compactQuick.Children.Add($button)
    }
    foreach ($action in @('Restore saved','Use defaults')) {
        $button=New-Object Windows.Controls.Button; $button.Content=if ($action -eq 'Restore saved') {'Undo'} else {'Default'}; $button.Padding='8,3'; $button.Margin='0,0,5,4'; $button.Tag=@{Form=$form;Action=$action}
        $button.ToolTip=if ($action -eq 'Use defaults') {'Select Save to remove both overrides from this scope. Other scopes do not change.'} else {'Restore the saved values. Remove the unsaved values.'}
        $button.Add_Click({param($sender,$eventArgs)
            $f=$sender.Tag.Form
            if ($sender.Tag.Action -eq 'Restore saved') { Set-LimitFormScope $f $f.Path $f.Card }
            else { $f.Loading=$true; $f.Window.Text='default'; $f.Compact.Text='default'; $f.Loading=$false; Update-CompactPercentageHint $f }
        }); [void]$resetRow.Children.Add($button)
    }
    foreach ($field in @($windowField,$compactField)) {
        $field.Tag=$form
        $field.Add_TextChanged({param($sender,$eventArgs)
            $f=$sender.Tag
            # Unknown baselines gain a stable, explicit base after valid entry.
            if (-not $f.Loading -and $f.Baseline -and -not $f.Baseline.Base) {
                try { $n=(ConvertTo-TokenLimit $f.Window.Text $null).Limit
                    if ($n -gt 0) { $f.Baseline.Base=$n; $f.Baseline.Source='entered window'; $f.BaseLabel.Text='Base: {0:N0} (entered window)' -f $n }
                } catch { }
            }
            Update-CompactPercentageHint $f
        })
    }
    $save.Tag=$form
    $save.Add_Click({param($sender,$eventArgs)
        $f=$sender.Tag
        try {
            if ($script:coreError) { throw $script:coreError }
            $draft=ConvertTo-ContextDraft $f.Window.Text $f.Compact.Text
            [void](Set-ContextLimits $f.Path @{model_context_window=$draft.Window;model_auto_compact_token_limit=$draft.Compact})
            Set-LimitFormScope $f $f.Path $f.Card
            $script:pendingLimits=$true
            if((Get-WidgetRestartStatus).Status -notin @('Waiting','Closing')){Write-RestartStatus $script:restartStatusPath 'Saved' 'Saved limits need a fresh Codex session.'}
            Update-LimitRestartControls
            $f.Result.Tag='Saved'; $f.Result.Text='CTC saved these values. The running chat keeps its current window. After all chats stop, quit Codex. Open Codex again.'
        } catch { $f.Result.Tag='Error'; $f.Result.Text=$_.Exception.Message }
    })
    $form.RestartView=Add-LimitRestartControls $resetRow.Parent
    return $form
}
function New-InlineLimitsEditor([string]$project,$card=$null) {
    $expander=New-Object Windows.Controls.Expander; $expander.Header='Edit context limits'; $expander.Foreground='#E0E1DD'; $expander.Margin='0,8,0,0'
    $panel=New-Object Windows.Controls.StackPanel; $expander.Content=$panel
    $current=New-Label '' 10; [void]$panel.Children.Add($current)
    $grid=New-Object Windows.Controls.Grid
    foreach ($width in @('*','8','*')) { $column=New-Object Windows.Controls.ColumnDefinition; $column.Width=$width; [void]$grid.ColumnDefinitions.Add($column) }
    $left=New-Object Windows.Controls.StackPanel; $right=New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($right,2)
    [void]$grid.Children.Add($left); [void]$grid.Children.Add($right); [void]$panel.Children.Add($grid)
    [void]$left.Children.Add((New-Label 'Context window' 10)); [void]$right.Children.Add((New-Label 'Compact at' 10))
    $w=New-Object Windows.Controls.TextBox; $w.Padding='8,4'; $w.Margin='0,3,0,3'; $w.ToolTip='Enter 200k or default.'; [void]$left.Children.Add($w)
    $quick=New-Object Windows.Controls.StackPanel; [void]$left.Children.Add($quick)
    $c=New-Object Windows.Controls.TextBox; $c.Padding='8,4'; $c.Margin='0,3,0,3'; $c.ToolTip='Enter 180k, 90%, or default.'; [void]$right.Children.Add($c)
    $presets=New-Object Windows.Controls.WrapPanel; [void]$right.Children.Add($presets)
    $resets=New-Object Windows.Controls.WrapPanel; $resets.Margin='0,4,0,0'; [void]$panel.Children.Add($resets)
    $hint=New-Label '' 10; [void]$panel.Children.Add($hint)
    [void]$panel.Children.Add((New-Label 'These project settings apply to all models. Larger values do not increase model capacity. A running chat needs a fresh session.' 10))
    $save=New-Object Windows.Controls.Button; $save.Content='Save project limits'; $save.Margin='0,5,0,5'; [void]$panel.Children.Add($save)
    $result=New-Label '' 10; [void]$panel.Children.Add($result)
    $form=Connect-LimitEditor $w $c $hint $current $quick $presets $resets $save $result
    Set-LimitFormScope $form (Join-Path $project '.codex/config.toml') $card
    $expander.Tag=$form
    Apply-WidgetTheme $expander
    return $expander
}
function Show-LimitEditorSurface {
    $FullPanel.Visibility='Collapsed'; $MiniPanel.Visibility='Collapsed'; $TokensPanel.Visibility='Collapsed'
    $SettingsHost.Content=$script:settings.dialog; $SettingsHost.Visibility='Visible'
    $LimitsMode.Tag='Selected'; $ContextMode.Tag=''; $TokenMode.Tag=''
    $window.FindName('AppearanceControls').Visibility='Collapsed'
}
function Show-Settings([string]$pane='Context') {
    if($script:settings.form.RestartView){[void]$script:restartControls.Remove($script:settings.form.RestartView)}
    $script:settings=@{}
    [xml]$settingsXaml=@'
<UserControl xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <DockPanel><StackPanel x:Name="LimitActions" DockPanel.Dock="Bottom"><TextBlock Text="These settings apply to all models. A running chat needs a fresh session. Model capacity does not increase." FontSize="10" Foreground="#778DA9" TextWrapping="Wrap" Margin="0,6,0,6"/><DockPanel><Button x:Name="BackTasks" DockPanel.Dock="Left" Content="Back" Padding="10,5" Margin="0,0,6,0"/><Button x:Name="SaveLimits" Content="Save limits" Padding="12,5"/></DockPanel><TextBlock x:Name="LimitResult" TextWrapping="Wrap" FontSize="10" Margin="0,4,0,0"/></StackPanel><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="0,0,10,0"><StackPanel x:Name="AppearanceSettings">
  <TextBlock Text="Window and startup" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,14"/>
  <TextBlock x:Name="OpacityLabel" Text="Background opacity"/>
  <Slider x:Name="OpacitySlider" Minimum="40" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" Margin="0,8,0,8"/>
  <TextBlock Text="40% shows more of the window below. 100% hides the window below. Text stays visible. CTC saves changes immediately." TextWrapping="Wrap" Foreground="#E0E1DD" Margin="0,0,0,12"/>
  <TextBlock Text="Corner placement (current screen)"/>
  <ComboBox x:Name="Corner" Margin="0,4,0,10"><ComboBoxItem Content="Free position"/><ComboBoxItem Content="Top left"/><ComboBoxItem Content="Top right"/><ComboBoxItem Content="Bottom left"/><ComboBoxItem Content="Bottom right"/></ComboBox>
  <Expander Header="Move and resize" Margin="0,0,0,12"><TextBlock Text="Drag the header to move the widget. Release near a corner to set the position. Select Expand or Collapse to change size. Drag the lower right control to resize the expanded view." FontSize="11" TextWrapping="Wrap"/></Expander>
  <CheckBox x:Name="Auto" Content="Auto-open with app" ToolTip="Start the app watcher at Windows sign-in." Margin="0,0,0,10"/>
  <TextBlock Text="App to follow"/><ComboBox x:Name="Target" Margin="0,4,0,10"><ComboBoxItem Content="Codex"/><ComboBoxItem Content="ChatGPT"/><ComboBoxItem Content="Either"/></ComboBox>
  <TextBlock TextWrapping="Wrap" Foreground="#E0E1DD" Text="The widget stays open after the app closes. Minimize puts the widget on the taskbar. Tray hides it beside the clock. Close stops CTC. Auto-open starts CTC when the app opens again."/>
  <Button x:Name="SaveApp" Content="Save window preferences" Padding="10" Margin="0,12,0,20"/><Button x:Name="WidgetBack" Content="Back" Padding="10"/>
  </StackPanel><StackPanel x:Name="ContextSettings">
  <ComboBox x:Name="Scope" MinHeight="30" Margin="0,0,0,6" ToolTip="Select the scope. Project settings apply to all models in that project. Global settings apply across projects."/>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <StackPanel><TextBlock Text="Context window" FontSize="11"/><TextBox x:Name="Context" Padding="8,4" MinHeight="30" Margin="0,3,0,0" ToolTip="Enter 200000, 200k, or default. This value is a token count."/><StackPanel x:Name="ContextQuick" Margin="0,4,0,0"/></StackPanel>
   <StackPanel Grid.Column="2"><TextBlock Text="Compact at" FontSize="11"/><TextBox x:Name="Compact" Padding="8,4" MinHeight="30" Margin="0,3,0,0" ToolTip="Enter 180k, 90%, or default. CTC converts the percentage to tokens when you select Save."/><WrapPanel x:Name="CompactQuick" Margin="0,4,0,0"/></StackPanel>
  </Grid>
  <WrapPanel x:Name="ResetQuick" Margin="0,4,0,0"/>
  <TextBlock x:Name="CompactHint" FontSize="10" TextWrapping="Wrap" Margin="0,3,0,6"/>
  <Expander Header="Saved and live values" FontSize="11" Margin="0,0,0,4"><TextBlock x:Name="Current" FontSize="10" TextWrapping="Wrap"/></Expander>
  <Expander Header="How limits work" FontSize="11" Foreground="#E0E1DD"><TextBlock Text="2x and 3x use the displayed base value. They do not multiply the previous result. Token thresholds keep their percentage. Default stays default. To remove both overrides, select Default. Then select Save. CTC saves percentages as tokens. They do not change with later window settings. The recorded chat window can be smaller than the saved value. Model catalog data can be old. Other models can have different limits. Move the pointer over the saved values to see the file path." FontSize="10" Margin="0,6,0,6" TextWrapping="Wrap"/></Expander>
  </StackPanel><TextBlock x:Name="Result" TextWrapping="Wrap" Foreground="#778DA9"/>
 </StackPanel></ScrollViewer></DockPanel>
</UserControl>
'@
    $script:settings.dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($settingsXaml))
    $script:settings.auto=$script:settings.dialog.FindName('Auto'); $script:settings.target=$script:settings.dialog.FindName('Target'); $script:settings.scope=$script:settings.dialog.FindName('Scope')
    $script:settings.current=$script:settings.dialog.FindName('Current'); $script:settings.context=$script:settings.dialog.FindName('Context'); $script:settings.compact=$script:settings.dialog.FindName('Compact'); $script:settings.result=$script:settings.dialog.FindName('Result')
    $script:settings.result=$script:settings.dialog.FindName('LimitResult')
    $script:settings.form=Connect-LimitEditor $script:settings.context $script:settings.compact ($script:settings.dialog.FindName('CompactHint')) $script:settings.current ($script:settings.dialog.FindName('ContextQuick')) ($script:settings.dialog.FindName('CompactQuick')) ($script:settings.dialog.FindName('ResetQuick')) ($script:settings.dialog.FindName('SaveLimits')) $script:settings.result
    $script:settings.opacitySlider=$script:settings.dialog.FindName('OpacitySlider'); $script:settings.opacityLabel=$script:settings.dialog.FindName('OpacityLabel'); $script:settings.corner=$script:settings.dialog.FindName('Corner')
    $script:settings.opacitySlider.Value=$window.Content.Background.Opacity*100; $script:settings.opacityLabel.Text='Background opacity: {0:N0}%' -f $script:settings.opacitySlider.Value
    $script:settings.opacitySlider.Add_ValueChanged({
        $LiveOpacity.Value=$script:settings.opacitySlider.Value
        $script:settings.opacityLabel.Text='Background opacity: {0:N0}%' -f $script:settings.opacitySlider.Value; Save-Preferences
    })
    $script:settings.corner.SelectedIndex=@('Free','TopLeft','TopRight','BottomLeft','BottomRight').IndexOf([string]$prefs.Corner)
    $script:settings.corner.Add_SelectionChanged({
        $prefs.Corner=@('Free','TopLeft','TopRight','BottomLeft','BottomRight')[$script:settings.corner.SelectedIndex]
        Position-Widget; Save-Preferences
    })
    $script:settings.auto.IsChecked=[bool]$prefs.AutoOpen
    $script:settings.target.SelectedIndex=@('Codex','ChatGPT','Either').IndexOf([string]$prefs.Target)
    $scopes=New-Object Collections.Generic.List[object]
    $scopes.Add([pscustomobject]@{ Label='Global - all projects'; Path=$script:configPath; Card=$null })
    $seen=@{}
    foreach ($card in @($script:shared.Latest.Cards)) {
        if ($card.Cwd -and -not $seen.ContainsKey($card.Cwd)) {
            $seen[$card.Cwd]=$true
            $scopes.Add([pscustomobject]@{ Label="Project - $(Split-Path $card.Cwd -Leaf)"; Path=(Join-Path $card.Cwd '.codex\config.toml'); Card=$card })
        }
    }
    foreach ($project in @($script:shared.Latest.Projects)) {
        if ($project -and -not $seen.ContainsKey($project)) {
            $seen[$project]=$true
            $scopes.Add([pscustomobject]@{Label="Project - $(Split-Path $project -Leaf) (idle)";Path=(Join-Path $project '.codex/config.toml');Card=$null})
        }
    }
    $script:settings.scope.DisplayMemberPath='Label'; $script:settings.scope.ItemsSource=$scopes
    $script:settings.scope.Add_SelectionChanged({
        try {
            $choice=$script:settings.scope.SelectedItem
            $script:settings.scope.ToolTip=$choice.Path
            Set-LimitFormScope $script:settings.form $choice.Path $choice.Card
        } catch { $script:settings.result.Tag='Error'; $script:settings.result.Text=$_.Exception.Message }
    })
    $script:settings.scope.SelectedIndex=0
    $script:settings.dialog.FindName('SaveApp').Add_Click({
        $script:settings.result=$script:settings.dialog.FindName('Result')
        try {
            Set-OverlayStartup ([bool]$script:settings.auto.IsChecked) $script:folder
            $prefs.AutoOpen=[bool]$script:settings.auto.IsChecked; $prefs.Target=[string]$script:settings.target.SelectedItem.Content; Save-Preferences
            if ($prefs.AutoOpen) { Start-Watcher }
            $script:settings.result.Foreground='#778DA9'; $script:settings.result.Text='CTC saved the window settings. Startup applies to your Windows account only.'
        } catch { $script:settings.result.Tag='Error'; $script:settings.result.Foreground='#778DA9'; $script:settings.result.Text=$_.Exception.Message }
    })
    if ($TestSettings -and $TestSeconds -gt 0) {
        & {
            try {
                $script:settings.context.Text='invalid'; $script:settings.compact.Text='180k'
                $script:settings.dialog.FindName('SaveLimits').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($script:settings.result.Tag -ne 'Error') { throw 'Invalid settings were not rejected.' }
                $script:settings.context.Text='500k'; $script:settings.compact.Text='36%'
                $script:settings.dialog.FindName('SaveLimits').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ((Get-TopLevelContextWindow $script:settings.scope.SelectedItem.Path) -ne 500000 -or (Get-TopLevelAutoCompactLimit $script:settings.scope.SelectedItem.Path) -ne 180000) { throw 'Settings buttons failed to save.' }
                $script:settingsTestPassed=$true
                $script:settings.opacitySlider.Value=65
                if ([Math]::Abs($window.Content.Background.Opacity-0.65) -gt 0.001) { throw 'Opacity slider failed.' }
                $script:settings.corner.SelectedIndex=1
                $workArea=Get-WidgetWorkArea
                if ([Math]::Abs($window.Left-($workArea.Left+12)) -gt 1 -or [Math]::Abs($window.Top-($workArea.Top+12)) -gt 1) { throw 'Corner selection failed.' }
                $savedPrefs=Get-Content -LiteralPath $script:preferencesPath -Raw | ConvertFrom-Json
                if ($savedPrefs.Opacity -ne 0.65 -or $savedPrefs.Corner -ne 'TopLeft') { throw 'Widget preferences not persisted.' }
                $script:widgetSettingsPassed=$true
            } catch { $script:settingsTestError=$_.Exception.Message }
        }
    }
    if ($pane -eq 'Widget') { Set-WidgetCompact $false }
    $FullPanel.Visibility='Collapsed'; $TokensPanel.Visibility='Collapsed'; $MiniPanel.Visibility='Collapsed'
    $SettingsHost.Content=$script:settings.dialog; $SettingsHost.Visibility='Visible'
    $LimitsMode.Tag=if ($pane -eq 'Context') {'Selected'} else {''}; $ContextMode.Tag=''; $TokenMode.Tag=''
    Apply-WidgetTheme $script:settings.dialog
    $script:settings.dialog.FindName('AppearanceSettings').Visibility=if ($pane -eq 'Widget') {'Visible'} else {'Collapsed'}
    $script:settings.dialog.FindName('ContextSettings').Visibility=if ($pane -eq 'Context') {'Visible'} else {'Collapsed'}
    $script:settings.dialog.FindName('LimitActions').Visibility=if ($pane -eq 'Context') {'Visible'} else {'Collapsed'}
    $window.FindName('AppearanceControls').Visibility=if ($pane -eq 'Context') {'Collapsed'} else {'Visible'}
    if ($pane -eq 'Context') { Show-LimitEditorSurface }
    $script:settings.dialog.FindName('BackTasks').Add_Click({ Set-WidgetCompact ([bool]$prefs.Compact) })
    $script:settings.dialog.FindName('WidgetBack').Add_Click({ Set-WidgetCompact ([bool]$prefs.Compact) })
}
function Start-Watcher {
    $watchScript=Join-Path $script:folder 'Watch-App.ps1'
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$watchScript+'"')
}
$script:tray=New-Object Windows.Forms.NotifyIcon
$script:trayIcon=New-Object Drawing.Icon((Join-Path $script:folder 'Context.ico'))
$tray.Icon=$script:trayIcon; $tray.Text='CTC - select to restore'; $tray.Visible=$true
[xml]$tabXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Context-Token Codex bar" Width="370" Height="88" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True" Foreground="#E0E1DD">
 <Border CornerRadius="10" Background="#0D1B2A" BorderBrush="#415A77" BorderThickness="1" Padding="10,7">
  <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <TextBlock x:Name="ParkTitle" Text="No active chats" FontSize="11" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,8,0"/>
    <StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="ParkPrevious" Content="&#x2039;" ToolTip="Previous chat"/><Button x:Name="ParkNext" Content="&#x203A;" ToolTip="Next chat"/><Button x:Name="ParkRestore" Content="&#x2197;" ToolTip="Restore the widget"/></StackPanel>
   </Grid>
   <Grid Grid.Row="1" Margin="0,5,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock x:Name="ParkContext" FontSize="14" Text="Context --"/><TextBlock x:Name="ParkTokens" Grid.Column="1" FontSize="14" Text="Tokens --" HorizontalAlignment="Right"/></Grid>
   <TextBlock x:Name="ParkQuota" Grid.Row="2" FontSize="10" Foreground="#778DA9" Margin="0,4,0,0" Text="5h -- left  |  7d -- left"/>
  </Grid>
 </Border>
</Window>
'@
$script:restoreTab=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($tabXaml))
foreach($name in @('Title','Context','Tokens','Quota','Previous','Next','Restore')){Set-Variable -Name ('park'+$name) -Value $restoreTab.FindName('Park'+$name) -Scope Script}
foreach($button in @($parkPrevious,$parkNext,$parkRestore)){$button.Style=$window.Resources[[Windows.Controls.Button]];$button.Width=24;$button.Height=22;$button.Padding=0;$button.Margin='3,0,0,0'}
$parkPrevious.Add_Click({Select-WidgetTask -1});$parkNext.Add_Click({Select-WidgetTask 1});$parkRestore.Add_Click({Show-Overlay})
$menu=New-Object Windows.Forms.ContextMenuStrip
$restore=$menu.Items.Add('Show overlay'); $restore.Add_Click({ Show-Overlay })
$hide=$menu.Items.Add('Hide to notification area'); $hide.Add_Click({ Hide-Overlay $false })
$settingsItem=$menu.Items.Add('Settings'); $settingsItem.Add_Click({ Show-Overlay; Show-Settings })
$exitItem=$menu.Items.Add('Exit'); $exitItem.Add_Click({ $window.Close() })
$tray.ContextMenuStrip=$menu
$tray.Add_MouseClick({ param($sender,$eventArgs) if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) { Show-Overlay } })
$DirectTray.Add_Click({ Hide-Overlay $false }); $TrayButton.Add_Click({ Hide-Overlay $true }); $ParkButton.Add_Click({ Hide-Overlay $true }); $SettingsButton.Add_Click({ Show-Settings })
$QuickSettings.Add_Click({ Show-Settings 'Widget' })
$Pin.Add_Click({ $window.Topmost=[bool]$Pin.IsChecked; $prefs.Topmost=[bool]$Pin.IsChecked; Sync-Pin; Save-Preferences })
$script:lastSnapshot=$null
$timer=New-Object Windows.Threading.DispatcherTimer; $timer.Interval=[TimeSpan]::FromMilliseconds(500)
$started=[DateTime]::UtcNow
$script:testPassed=$false
$timer.Add_Tick({
    try {
        if ($TestSeconds -gt 0 -and -not $script:hiddenTestStarted -and ([DateTime]::UtcNow-$started).TotalSeconds -ge 1) {
            $script:hiddenTestStarted=[DateTime]::UtcNow
            $window.Hide()
            return
        }
        if ($TestSeconds -gt 0 -and $script:hiddenTestStarted -and -not $script:hiddenLoopPassed) {
            if (([DateTime]::UtcNow-$script:hiddenTestStarted).TotalMilliseconds -lt 600) { return }
            $script:hiddenLoopPassed=(-not $window.IsVisible -and $tray.Visible)
            Show-Overlay
        }
        if ($showEvent.WaitOne(0)) { Show-Overlay }
        Update-ContextQuotaBars
        Update-ParkedBar
        Update-LimitRestartControls
        if ($prefs.Mode -eq 'Tokens') { Update-TokenPanel }
        if ($script:shared.Error) { $Health.Text='Data unavailable: '+$script:shared.Error; $MiniStatus.Text='Data unavailable - open for details' }
        $snapshot=$script:shared.Latest
        if ($snapshot -and -not [object]::ReferenceEquals($snapshot,$script:lastSnapshot)) {
            Update-Cards $snapshot
            $Health.Text='Updated '+$snapshot.Updated.ToLocalTime().ToString('HH:mm:ss'); $Health.ToolTip="$($snapshot.Discovery) | Compaction: $($snapshot.Compaction)"
            if ($snapshot.Warning) { $Health.Text+=' | Limited data'; $Health.ToolTip+="`n$($snapshot.Warning)" }
            $script:lastSnapshot=$snapshot
        }
        if ($TestSettings -and -not $script:liveTokenTestAppended -and $shared.Latest.Tokens.Tasks -gt 0) {
            $script:liveTokenTestAppended=$true
            $testRecord=@{type='event_msg';timestamp=[DateTimeOffset]::Now.ToString('o');payload=@{type='token_count';info=@{total_token_usage=@{total_tokens=90000;input_tokens=88000;cached_input_tokens=22000;output_tokens=2000;reasoning_output_tokens=1000}}}} | ConvertTo-Json -Depth 8 -Compress
            [IO.File]::AppendAllText((Join-Path $CodexHome 'sessions/test.jsonl'),$testRecord+"`n")
        }
        if ($TestSeconds -gt 0 -and ([DateTime]::UtcNow-$started).TotalSeconds -ge $TestSeconds) {
            $timer.Stop()
            if ($TestSettings) {
                Set-WidgetCompact $true
                $MiniEditContext.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if (-not $prefs.Compact -or $window.Width -ne 370 -or $SettingsHost.Visibility -ne 'Visible' -or $script:settings.scope.SelectedItem.Path -ne (Join-Path $CodexHome '.codex/config.toml')) { throw 'Mini context editor failed.' }
                $script:settings.context.Text='200k'; $script:settings.compact.Text='90%'
                $miniBase=$script:settings.form.Baseline.Base
                $script:settings.form.ScaleButtons[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($script:settings.context.Text -ne [string]($miniBase*2) -or $script:settings.compact.Text -ne '90%') { throw "Mini 2x preview failed: base=$miniBase window=$($script:settings.context.Text) compact=$($script:settings.compact.Text) result=$($script:settings.result.Text)" }
                $script:settings.form.ScaleButtons[2].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($script:settings.context.Text -ne [string]($miniBase*3)) { throw 'Mini 3x compounded instead of using base.' }
                if (-not $script:settings.dialog.FindName('SaveLimits').IsEnabled) { throw 'Valid mini draft not enabled.' }
                $draftWindow=$script:settings.context.Text; $formBeforeToggle=$script:settings.form
                $ToggleButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($prefs.Compact -or $SettingsHost.Visibility -ne 'Visible' -or $script:settings.context.Text -ne $draftWindow -or -not [object]::ReferenceEquals($formBeforeToggle,$script:settings.form)) { throw 'Expand lost context draft.' }
                $ToggleButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if (-not $prefs.Compact -or $SettingsHost.Visibility -ne 'Visible') { throw 'Collapse did not retain editor.' }
                $window.UpdateLayout()
                foreach ($field in @($script:settings.context,$script:settings.compact,$script:settings.dialog.FindName('SaveLimits'))) {
                    $point=$field.TranslatePoint([Windows.Point]::new(0,0),$window)
                    if ($point.Y -lt 0 -or $point.Y+$field.ActualHeight -gt $window.ActualHeight) { throw 'Mini editor field or save button outside window.' }
                }
                # Observe provider bounds without treating a cached maximum as a guarantee.
                $script:settings.form.Baseline.Maximum=200000
                $script:settings.context.Text='800k'
                if ($script:settings.result.Tag -ne 'Warning' -or $script:settings.result.Text -notlike '*reject or reduce*') { throw 'Catalog limit warning missing.' }
                $script:settings.context.Text='100k'; $script:settings.compact.Text='101k'
                if ($script:settings.dialog.FindName('SaveLimits').IsEnabled -or $script:settings.result.Tag -ne 'Error') { throw 'Invalid compact threshold enabled Save.' }
                $script:settings.context.Text=[string]($miniBase*3); $script:settings.compact.Text='90%'
                $script:settings.form.Baseline.Maximum=$null
                Update-CompactPercentageHint $script:settings.form
                if ($TestReport) {
                    $window.UpdateLayout()
                    $miniBitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                    $miniBitmap.Render($window); $miniEncoder=New-Object Windows.Media.Imaging.PngBitmapEncoder; $miniEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($miniBitmap))
                    $miniStream=[IO.File]::Create($TestReport+'.mini-limits.png'); try { $miniEncoder.Save($miniStream) } finally { $miniStream.Dispose() }
                }
                $inline=New-InlineLimitsEditor $CodexHome
                $inlineSave=@($inline.Content.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0]
                $inlineSave.Tag.Window.Text='200k'; $inlineSave.Tag.Compact.Text='90%'
                if ($inlineSave.Tag.Compact.Tag.Hint.Text -notlike (('{0:N1}%' -f 90.0)+'*')) { throw 'Compact percentage example did not update.' }
                $inlineSave.Tag.Window.Text='1000k'
                $inlineSave.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ((Get-TopLevelContextWindow $inlineSave.Tag.Path) -ne 1000000 -or (Get-TopLevelAutoCompactLimit $inlineSave.Tag.Path) -ne 900000) { throw 'Inline chat limit edit failed.' }
                $LimitsMode.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($SettingsHost.Visibility -ne 'Visible' -or $SettingsHost.Content -isnot [Windows.Controls.UserControl]) { throw 'Settings did not open inside the overlay.' }
                $idleChoice=@($script:settings.scope.Items | Where-Object Label -like '*(idle)')[0]
                if (-not $idleChoice) { throw 'Idle project scope missing from editor.' }
                $script:settings.scope.SelectedItem=$idleChoice
                $script:settings.context.Text='200k'; $script:settings.compact.Text='90%'
                $script:settings.dialog.FindName('SaveLimits').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ((Get-TopLevelAutoCompactLimit $idleChoice.Path) -ne 180000) { throw "Idle project percentage save failed: path=$($idleChoice.Path) selected=$($script:settings.form.Path) result=$($script:settings.result.Text)" }
                $quickRow=$script:settings.form.ResetRow
                $undo=@($quickRow.Children | Where-Object Content -eq 'Undo')[0]
                $defaults=@($quickRow.Children | Where-Object Content -eq 'Default')[0]
                $script:settings.context.Text='300k'; $undo.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($script:settings.context.Text -ne '200000' -or $script:settings.dialog.FindName('SaveLimits').IsEnabled) { throw 'Undo did not restore saved values.' }
                $defaults.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ((Get-TopLevelContextWindow $idleChoice.Path) -ne 200000) { throw 'Default preview wrote before Save.' }
                $script:settings.dialog.FindName('SaveLimits').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($null -ne (Get-TopLevelContextWindow $idleChoice.Path)) { throw 'Default save did not remove project override.' }
                $script:settings.scope.SelectedIndex=0
                # Exercise handlers after Show-Settings has returned (no modal local scope).
                $script:settings.context.Text='500k'; $script:settings.compact.Text='36%'
                $script:settings.dialog.FindName('SaveLimits').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ((Get-TopLevelContextWindow $script:settings.scope.SelectedItem.Path) -ne 500000) { throw 'Embedded settings save failed after return.' }
                if ($TestReport) {
                Set-WidgetCompact $false
                Show-LimitEditorSurface
                $window.UpdateLayout()
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                    $bitmap.Render($window); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create($TestReport+'.settings.png')
                    try { $encoder.Save($stream) } finally { $stream.Dispose() }
                }
            }
            Set-WidgetCompact $false
            $window.UpdateLayout()
            if ($TestReport) {
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window)
                $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream=[IO.File]::Create($TestReport+'.png'); try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            if ($window.Height -lt [Math]::Min(520,(Get-WidgetWorkArea).Height)) {throw 'Expanded viewport is below the supported minimum.'}
            $expandedWidth=$window.Width
            $ToggleButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            $window.UpdateLayout()
            $LiveOpacity.Value=55
            $directOpacityPassed=($window.Opacity -eq 1 -and [Math]::Abs($window.Content.Background.Opacity-0.55) -lt 0.001 -and $LiveOpacityLabel.Text -eq '55%'); $window.UpdateLayout()
            $miniViewport=$MiniPanel.Parent
            $buttonBottom=$MiniEditContext.TranslatePoint([Windows.Point]::new(0,$MiniEditContext.ActualHeight),$miniViewport).Y
            if ($buttonBottom -gt $miniViewport.ActualHeight) { throw 'Mini context button is clipped by the content viewport.' }
            foreach ($counter in @('2 / 2','128 / 128')) {
                $TaskPosition.Text=$counter; $window.UpdateLayout()
                $left=$PreviousTask.TranslatePoint([Windows.Point]::new($PreviousTask.ActualWidth,0),$MiniPanel).X
                $textLeft=$TaskPosition.TranslatePoint([Windows.Point]::new(0,0),$MiniPanel).X
                $textRight=$TaskPosition.TranslatePoint([Windows.Point]::new($TaskPosition.ActualWidth,0),$MiniPanel).X
                $right=$NextTask.TranslatePoint([Windows.Point]::new(0,0),$MiniPanel).X
                if ($textLeft-$left -lt 7 -or $right-$textRight -lt 7) {throw 'Navigation counter overlaps an arrow.'}
            }
            $TaskPosition.Text='2 / 2'; $window.UpdateLayout()
            $compactPassed=($prefs.Compact -and $window.Width -eq 370 -and $FullPanel.Visibility -eq 'Collapsed' -and $window.WindowStyle -eq 'None' -and $window.AllowsTransparency -and $directOpacityPassed)
            if ($TestReport) {
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream=[IO.File]::Create($TestReport+'.mini.png'); try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            $ToggleButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            $compactPassed=$compactPassed -and -not $prefs.Compact -and $window.Width -eq $expandedWidth
            $workArea=Get-WidgetWorkArea
            $window.Left=$workArea.Right-$window.Width-20; $window.Top=$workArea.Bottom-$window.Height-20
            Position-Widget -Snap
            $snapPassed=($prefs.Corner -eq 'BottomRight')
            $TokenMode.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            $shared.LiveQuota=ConvertTo-QuotaSnapshot ([pscustomobject]@{rateLimits=[pscustomobject]@{planType='plus';primary=[pscustomobject]@{usedPercent=35;windowDurationMins=300;resetsAt=[DateTimeOffset]::Now.AddHours(2).ToUnixTimeSeconds()};secondary=[pscustomobject]@{usedPercent=72;windowDurationMins=10080;resetsAt=[DateTimeOffset]::Now.AddDays(3).ToUnixTimeSeconds()}}}) 'Test quota' ([DateTimeOffset]::Now)
            Update-TokenPanel
            if ($TestSettings -and ($shared.Latest.Tokens.Total -ne 90000 -or $script:tokenMetricRows.Reasoning.Text -ne (Format-TokenValue 1000) -or $script:tokenTaskRows.Count -ne 1)) { throw 'Live token append did not reach the UI with detailed counters.' }
            if ($TestSettings) {
                if ($ActiveTokenTasks.Children.Count -ne 1 -or $TokenSummary.IsExpanded) { throw 'Active chat was not the primary token highlight.' }
                $originalSnapshot=$shared.Latest
                $fixtureTokens=$originalSnapshot.Tokens|Select-Object *
                $fixtureTokens.Rows=@(1..40|ForEach-Object { $item=$originalSnapshot.Tokens.Rows[0]|Select-Object *; $item.Id="scroll-$_"; $item.Title="Active chat $_"; $item })
                $fixtureTokens.ActiveRows=$fixtureTokens.Rows
                # Use a fixed snapshot; the live worker continues independently.
                Update-TokenPanel $fixtureTokens; $window.UpdateLayout(); $TokensPanel.ScrollToVerticalOffset(0); $window.UpdateLayout()
                $wheel=[Windows.Input.MouseWheelEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,-120)
                $wheel.RoutedEvent=[Windows.UIElement]::PreviewMouseWheelEvent; $TokensPanel.RaiseEvent($wheel); $window.UpdateLayout()
                if ([Math]::Abs($TokensPanel.VerticalOffset-24) -gt 1) { throw 'Long-list wheel step was not 24 pixels.' }
                Update-TokenPanel $fixtureTokens; $window.UpdateLayout()
                if ([Math]::Abs($TokensPanel.VerticalOffset-24) -gt 1) { throw 'Live refresh changed the scroll position.' }
                Update-TokenPanel $originalSnapshot.Tokens; $TokensPanel.ScrollToVerticalOffset(0)
            }
            Update-ContextQuotaBars
        Update-ParkedBar
            if ($script:contextQuotaRows.Count -ne 2 -or @($script:contextQuotaRows.Values | Where-Object {$_.Bar.Value -eq 65}).Count -ne 1) { throw 'Context quota bars failed.' }
            if ($TokensPanel.Visibility -ne 'Visible' -or $prefs.Mode -ne 'Tokens' -or $script:contextQuotaRows.Count -ne 2) { throw 'Tokens mode switch or quota rendering failed.' }
            $window.UpdateLayout()
            if ($TestReport) {
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create($TestReport+'.tokens.png')
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            if ($TestReport -and $script:tokenTaskRows.Count -gt 0) {
                $detailRow=@($script:tokenTaskRows.Values)[0]; $detailRow.Expand.IsExpanded=$true; $window.UpdateLayout()
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create($TestReport+'.details.png')
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
                $detailRow.Expand.IsExpanded=$false
            }
            $ContextMode.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            if ($TokensPanel.Visibility -ne 'Collapsed' -or $prefs.Mode -ne 'Context') { throw 'Context mode did not restore.' }
            $window.UpdateLayout()
            if ($TestReport) {
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create($TestReport+'.quotabars.png')
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            if ($UserWebsite.NavigateUri.AbsoluteUri -ne 'https://yahyanabil.com/' -or $AuthorLine.Text -ne 'By Yahya Nabil') { throw 'Attribution controls missing.' }
            $MinimizeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)); $minimized=($window.WindowState -eq 'Minimized')
            foreach($corner in @('TopLeft','TopRight','BottomLeft','BottomRight')) {
                $prefs.Corner=$corner; Hide-Overlay $true; $restoreTab.UpdateLayout()
                $expectedLeft=if($corner.EndsWith('Left')){$workArea.Left+12}else{$workArea.Right-$restoreTab.Width-12}
                $expectedTop=if($corner.StartsWith('Top')){$workArea.Top+12}else{$workArea.Bottom-$restoreTab.Height-12}
                if([Math]::Abs($restoreTab.Left-$expectedLeft) -gt 1 -or [Math]::Abs($restoreTab.Top-$expectedTop) -gt 1){throw 'Parked bar changed its selected corner.'}
            }
            if($parkQuota.Text -notmatch '65%' -or $parkTokens.Text -eq 'Tokens --'){throw 'Parked bar omitted token or quota data.'}
            if($TestReport){
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$restoreTab.ActualWidth,[int]$restoreTab.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($restoreTab);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream=[IO.File]::Create($TestReport+'.park.png');try{$encoder.Save($stream)}finally{$stream.Dispose()}
            }
            Show-Overlay
            if($TestSettings){
                foreach($view in $script:restartControls){if($view.Now.IsEnabled){throw 'Restart now was enabled for a running chat.'}}
                $detailView=@($script:tokenTaskRows.Values)[0].Detail
                if($detailView.Values.Input.Text -ne (Format-ShortTokenValue 88000)){throw 'Token cards missed live counters.'}
            }
            Show-Overlay; Hide-Overlay $true; $hidden=(-not $window.IsVisible -and $restoreTab.IsVisible -and $tray.Visible); Show-Overlay
            $script:testPassed=($script:shared.Scans -gt 0 -and $minimized -and $hidden -and $window.IsVisible -and -not $script:shared.Error)
            if (-not $script:hiddenLoopPassed -or -not $compactPassed -or -not $snapPassed -or ($TestSettings -and (-not $script:settingsTestPassed -or -not $script:widgetSettingsPassed))) { $script:testPassed=$false }
            if ($TestReport) { [IO.File]::WriteAllText($TestReport, (@{ Passed=$script:testPassed; HiddenLoopPassed=$script:hiddenLoopPassed; DirectOpacityPassed=$directOpacityPassed; Scans=$script:shared.Scans; Cards=$script:cardControls.Count; Minimized=$minimized; Hidden=$hidden; Restored=$window.IsVisible; Error=$script:shared.Error; SettingsPassed=$script:settingsTestPassed; SettingsError=$script:settingsTestError; CompactPassed=$compactPassed; SnapPassed=$snapPassed; WidgetSettingsPassed=$script:widgetSettingsPassed } | ConvertTo-Json)) }
            $window.Close()
        }
    } catch { $Health.Text='Overlay error: '+$_.Exception.Message
        if ($TestSeconds -gt 0) { if ($TestReport) { [IO.File]::WriteAllText($TestReport,$_.ToString()) }; $window.Close() }
    }
})
$window.Add_Closing({
    if ($TestSeconds -eq 0) {
        $bounds=$window.RestoreBounds
        if (-not $prefs.Compact) { $prefs.Width=$bounds.Width; $prefs.Height=$bounds.Height }
        $prefs.Left=$bounds.Left; $prefs.Top=$bounds.Top
        try { Save-Preferences } catch { }
    }
})
try {
    if ($TestSeconds -eq 0 -and $prefs.AutoOpen) { Save-Preferences; Set-OverlayStartup $true $script:folder; Start-Watcher }
    # A modal ShowDialog loop exits on Hide(), which used to dispose the tray icon.
    # Application.Run keeps the dispatcher alive until the user explicitly exits.
    $script:app=New-Object Windows.Application
    $app.ShutdownMode='OnExplicitShutdown'
    $window.Add_Closed({ $app.Shutdown() })
    $timer.Start(); [void]$app.Run($window)
} finally {
    $timer.Stop(); $opacitySaveTimer.Stop(); $restoreTab.Close(); $tray.Visible=$false; $tray.Dispose(); $script:trayIcon.Dispose(); $menu.Dispose()
    $shared.Stop=$true; $worker.Stop(); $worker.Dispose(); $quotaWorker.Stop(); $quotaWorker.Dispose(); $showEvent.Dispose();$readyEvent.Dispose()
    if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose()
}
if ($TestSeconds -gt 0 -and -not $script:testPassed) { exit 1 }
