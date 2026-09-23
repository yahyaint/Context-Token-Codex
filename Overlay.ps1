# SPDX-License-Identifier: MIT
param([switch]$Watch, [string]$CodexHome='', [string]$PreferencesPath='', [int]$TestSeconds=0, [string]$TestReport='', [switch]$TestSettings)
$ErrorActionPreference = 'Stop'
if ($TestSettings -and ($TestSeconds -lt 1 -or -not $CodexHome -or -not (Test-Path -LiteralPath (Join-Path $CodexHome '.overlay-test-fixture')))) { throw 'Settings test requires a marked disposable fixture and TestSeconds.' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class WidgetIdentity { [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id); }'
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
$script:shared = [hashtable]::Synchronized(@{ Stop=$false; Latest=$null; Error=''; Scans=0; Mode=$prefs.Mode; LiveQuota=$null; QuotaError=''; RefreshQuota=$false; Fetching=$false })
$worker = [PowerShell]::Create()
[void]$worker.AddScript({
    param($shared,$folder,$homePath)
    try {
        . (Join-Path $folder 'Monitor.Core.ps1') -CodexHome $homePath
        . (Join-Path $folder 'Monitor.Data.ps1')
        . (Join-Path $folder 'Usage.Provider.ps1')
        while (-not $shared.Stop) {
            try { $snapshot=Get-MonitorSnapshot; Update-SnapshotQuota $snapshot $shared.LiveQuota $CodexHome; $shared.Latest=$snapshot; $shared.Error=''; $shared.Scans++ }
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
        if (-not $testing -and $shared.Mode -eq 'Tokens' -and ($shared.RefreshQuota -or ([DateTime]::UtcNow-$last).TotalSeconds -ge 60)) {
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
try { . (Join-Path $PSScriptRoot 'Monitor.Core.ps1') -CodexHome $CodexHome } catch { $script:coreError=$_.Exception.Message }
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Context-Token Codex" Width="460" Height="620" MinWidth="300" MinHeight="150" Background="Transparent" Foreground="#E0E1DD" WindowStyle="None" AllowsTransparency="True" ResizeMode="NoResize" WindowStartupLocation="Manual">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="10,6"/><Setter Property="Margin" Value="0,0,6,0"/><Setter Property="Background" Value="#0D1B2A"/><Setter Property="Foreground" Value="#E0E1DD"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Chrome" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#778DA9"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#778DA9"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
 </Window.Resources>
 <Border BorderBrush="#778DA9" BorderThickness="1" CornerRadius="18" Padding="16">
 <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#0D1B2A" Offset="0"/><GradientStop Color="#0D1B2A" Offset="1"/></LinearGradientBrush></Border.Background>
 <Grid>
 <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
 <Grid x:Name="DragHandle" Background="Transparent" Margin="0,0,0,9" Cursor="SizeAll" ToolTip="Drag to move. Drop near a corner to snap.">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Image x:Name="BrandIcon" Width="22" Height="22" Margin="0,0,7,0"/><TextBlock Text="CTC" FontSize="11" Foreground="#778DA9" FontWeight="SemiBold"/></StackPanel>
  <StackPanel Grid.Column="1" Orientation="Horizontal">
   <Button x:Name="ToggleButton" Content="Expand" Padding="7,3" Margin="0,0,5,0" FontSize="11" ToolTip="Switch between mini card and full view"/>
   <Button x:Name="QuickContext" Width="28" Height="28" Padding="0" Margin="0,0,5,0" ToolTip="Context limits"><Viewbox Width="12" Height="12"><Canvas Width="16" Height="16"><Path Data="M1,4 L15,4 M1,12 L15,12" Stroke="#E0E1DD" StrokeThickness="1.5"/><Ellipse Canvas.Left="4" Canvas.Top="1" Width="5" Height="5" Fill="#778DA9"/><Ellipse Canvas.Left="9" Canvas.Top="9" Width="5" Height="5" Fill="#778DA9"/></Canvas></Viewbox></Button><Button x:Name="QuickSettings" Width="28" Height="28" FontSize="12" FontFamily="Segoe MDL2 Assets" Content="&#xE713;" Padding="0" Margin="0,0,5,0" ToolTip="Widget settings"/>
   <Button x:Name="MinimizeButton" Width="28" Height="28" Padding="0" Margin="0,0,5,0" ToolTip="Minimize to taskbar"><Path Data="M0,5 L10,5" Width="10" Height="10" Stroke="#E0E1DD" StrokeThickness="1.5"/></Button>
   <Button x:Name="CloseButton" Width="28" Height="28" Padding="0" Margin="0" ToolTip="Exit CTC"><Path Data="M1,1 L9,9 M1,9 L9,1" Width="10" Height="10" Stroke="#E0E1DD" StrokeThickness="1.5"/></Button>
  </StackPanel>
 </Grid>
 <WrapPanel Grid.Row="1" Margin="0,0,0,12"><Button x:Name="ContextMode" Content="Context" Padding="12,5" Margin="0,0,6,0"/><Button x:Name="TokenMode" Content="Tokens" Padding="12,5" Margin="0,0,6,0"/><Button x:Name="LimitsMode" Content="Limits" Padding="12,5" ToolTip="Edit context settings"/></WrapPanel><Grid Grid.Row="2">
 <StackPanel x:Name="MiniPanel" Background="Transparent">
  <TextBlock x:Name="MiniTitle" Text="Waiting for active chats" FontSize="17" FontWeight="SemiBold" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis" Cursor="Hand" ToolTip="Click chat name to expand"/>
  <TextBlock x:Name="MiniStatus" Text="Connecting..." FontSize="11" Foreground="#E0E1DD" Margin="0,5,0,6" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis"/>
  <Grid Margin="0,2,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="MiniPercent" Text="--" FontSize="30" FontWeight="SemiBold" Foreground="#778DA9"/><StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="CONTEXT USED" FontSize="9" Foreground="#E0E1DD" HorizontalAlignment="Right"/><TextBlock x:Name="MiniUsage" Text="Waiting for usage" FontSize="11" Foreground="#E0E1DD" HorizontalAlignment="Right"/></StackPanel></Grid>
  <ProgressBar x:Name="MiniBar" Height="6" Minimum="0" Maximum="100" Background="#0D1B2A" Foreground="#778DA9"/>
  <UniformGrid Columns="3" Margin="0,12,0,8">
   <StackPanel><TextBlock Text="REMAINING" FontSize="9" Foreground="#E0E1DD"/><TextBlock x:Name="MiniRemaining" Text="--" FontSize="15" Margin="0,3,0,0"/></StackPanel>
   <StackPanel><TextBlock Text="COMPACTIONS" FontSize="9" Foreground="#E0E1DD"/><TextBlock x:Name="MiniCompactions" Text="--" FontSize="15" Margin="0,3,0,0"/></StackPanel>
   <StackPanel><TextBlock Text="CACHED INPUT" FontSize="9" Foreground="#E0E1DD"/><TextBlock x:Name="MiniCached" Text="--" FontSize="15" Margin="0,3,0,0"/></StackPanel>
  </UniformGrid>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="MiniUpdated" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap" Text="Waiting for data" FontSize="10" Foreground="#E0E1DD" VerticalAlignment="Center"/><Grid Grid.Column="1" Margin="8,0,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions><Button x:Name="PreviousTask" Grid.Column="0" Content="&#x2039;" Width="28" Height="28" Padding="0" Margin="0" ToolTip="Previous active chat"/><TextBlock x:Name="TaskPosition" Grid.Column="1" Text="0 / 0" MinWidth="40" TextAlignment="Center" FontSize="10" VerticalAlignment="Center" Margin="8,0"/><Button x:Name="NextTask" Grid.Column="2" Content="&#x203A;" Width="28" Height="28" Padding="0" Margin="0" ToolTip="Next active chat"/></Grid></Grid>
  <Button x:Name="MiniEditContext" Content="Edit context limits" FontSize="11" Padding="10,3" HorizontalAlignment="Left" Margin="0,8,0,0" IsEnabled="False" ToolTip="Open the displayed chat project context editor. Applies to all models in that project."/><!-- mini shortcut --></StackPanel><ScrollViewer x:Name="TokensPanel" VerticalScrollBarVisibility="Auto" Visibility="Collapsed"><StackPanel Margin="0,0,8,0"><TextBlock x:Name="ActiveTokenHeading" Text="Active chats" FontSize="10" Foreground="#778DA9" Margin="0,0,0,6"/><StackPanel x:Name="ActiveTokenTasks"/><Expander x:Name="TokenSummary" Header="All loaded chats" Foreground="#E0E1DD" IsExpanded="True" Margin="0,0,0,8"><StackPanel>
  <DockPanel><TextBlock Text="Recorded totals" FontSize="10" Foreground="#778DA9"/><TextBlock x:Name="TokenLive" Text="Watching files" FontSize="10" HorizontalAlignment="Right"/></DockPanel>
  <TextBlock x:Name="TokenTotal" Text="Waiting for usage" FontSize="28" FontWeight="SemiBold" Margin="0,4,0,4"/>
  <TextBlock x:Name="TokenBreakdown" FontSize="10" Opacity="0.75" Margin="0,0,0,8"/>
  <UniformGrid x:Name="TokenMetrics" Columns="3" Margin="0,0,0,8"/>
  </StackPanel></Expander><Expander Header="Other chat details" Foreground="#E0E1DD" Margin="0,0,0,8"><StackPanel x:Name="TokenTasks"/></Expander>
  <DockPanel Margin="0,4,0,8"><Button x:Name="RefreshUsage" Content="Refresh" DockPanel.Dock="Right" FontSize="10" Padding="8,3"/><TextBlock x:Name="SubscriptionHeading" Text="Account quota used" FontSize="10" Foreground="#778DA9" VerticalAlignment="Center"/></DockPanel>
  <UniformGrid x:Name="QuotaCards" Columns="2"/>
  <Expander Header="Reading status" Margin="0,4,0,4"><TextBlock x:Name="TokenSource" Text="Reading subscription usage..." FontSize="10" Margin="0,4,0,6"/></Expander>
  <Expander Header="How counts work" Foreground="#E0E1DD"><TextBlock x:Name="TokenCoverage" FontSize="10" Opacity="0.85" Margin="0,6,0,0"/></Expander>
 </StackPanel></ScrollViewer>
 <ContentControl x:Name="SettingsHost" Visibility="Collapsed"/><DockPanel x:Name="FullPanel" Visibility="Collapsed">
  <StackPanel DockPanel.Dock="Top">
   <TextBlock Text="Active chats" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,4" ToolTip="Context-Token Codex"/>
   <WrapPanel Visibility="Collapsed"><Button x:Name="SettingsButton" Content="Context settings"/><Button x:Name="TrayButton" Content="Park at edge"/><CheckBox x:Name="Pin" Content="On top" Foreground="#E0E1DD" VerticalAlignment="Center"/></WrapPanel>
   <TextBlock x:Name="Health" Text="Connecting to local Codex data..." Foreground="#E0E1DD" FontSize="10" Margin="0,0,0,10"/>
  </StackPanel>
  <StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
   <UniformGrid x:Name="ContextQuotaBars" Columns="2"/>
   <TextBlock Text="Latest recorded context" ToolTip="Updates arrive after responses. Local Codex chats only." FontSize="10" Foreground="#778DA9" Margin="0,5,0,0"/>
  </StackPanel>
  <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Cards"/></ScrollViewer>
 </DockPanel>
 </Grid>
 <StackPanel Grid.Row="3" Margin="0,12,0,0"><TextBlock x:Name="AuthorLine" Text="By Yahya Nabil" FontSize="10" Opacity="0.75" HorizontalAlignment="Center" Margin="0,0,0,8"/>
  <Border Height="1" Background="#0D1B2A" Margin="0,0,0,10"/>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Background" FontSize="11" Foreground="#E0E1DD" VerticalAlignment="Center" Margin="0,0,10,0"/><Slider x:Name="LiveOpacity" Grid.Column="1" Minimum="40" Maximum="100" SmallChange="1" LargeChange="5" VerticalAlignment="Center" ToolTip="Drag to change background opacity live"/><TextBlock x:Name="LiveOpacityLabel" Grid.Column="2" Width="38" TextAlignment="Right" FontSize="11" VerticalAlignment="Center"/></Grid>
  <Grid Margin="0,9,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Grid.Column="1" FontSize="9" HorizontalAlignment="Center" VerticalAlignment="Center"><Hyperlink x:Name="UserWebsite" NavigateUri="https://yahyanabil.com" Foreground="#778DA9">yahyanabil.com</Hyperlink></TextBlock><StackPanel Orientation="Horizontal"><Button x:Name="QuickPin" Content="Pinned" FontSize="10" Padding="7,4" ToolTip="Toggle always on top"/><Button x:Name="QuickCorner" Content="Corner" FontSize="10" Padding="7,4" Margin="5,0,0,0" ToolTip="Choose a screen corner"/></StackPanel><StackPanel Grid.Column="2" Orientation="Horizontal"><Button x:Name="DirectTray" Content="Tray" FontSize="10" Padding="7,4" ToolTip="Hide here; restore with the CTC icon beside the Windows clock."/><Button x:Name="ParkButton" Content="Park" FontSize="10" Padding="8,4" Margin="5,0,0,0" ToolTip="Shrink to a visible restore tab. Click tab to return."/></StackPanel></Grid>
 </StackPanel>
 <Thumb x:Name="ResizeGrip" Grid.Row="2" Width="16" Height="16" HorizontalAlignment="Right" VerticalAlignment="Bottom" Cursor="SizeNWSE" Visibility="Collapsed" ToolTip="Drag to resize">
  <Thumb.Template><ControlTemplate TargetType="Thumb"><TextBlock Text="&#x25E2;" Foreground="#E0E1DD" Background="Transparent"/></ControlTemplate></Thumb.Template>
 </Thumb>
 </Grid>
 </Border>
</Window>
'@
$script:window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
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
foreach ($name in @('MiniEditContext','SettingsButton','TrayButton','Pin','Health','ContextQuotaBars','Cards','DragHandle','ToggleButton','QuickSettings','MinimizeButton','CloseButton','MiniPanel','FullPanel','MiniTitle','MiniStatus','MiniBar','MiniUsage','ResizeGrip','MiniPercent','MiniRemaining','MiniCompactions','MiniCached','MiniUpdated','PreviousTask','NextTask','TaskPosition','LiveOpacity','LiveOpacityLabel','QuickPin','QuickCorner','ParkButton','DirectTray','SettingsHost','QuickContext','ContextMode','TokenMode','LimitsMode','TokensPanel','TokenTotal','TokenLive','TokenMetrics','TokenTasks','ActiveTokenTasks','ActiveTokenHeading','TokenSummary','TokenBreakdown','TokenCoverage','QuotaCards','TokenSource','SubscriptionHeading','RefreshUsage','AuthorLine','UserWebsite')) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }
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
    $LimitsMode.Tag=''
    $ContextMode.Tag=if ($prefs.Mode -eq 'Context') {'Selected'} else {''}
    $TokenMode.Tag=if ($prefs.Mode -eq 'Tokens') {'Selected'} else {''}
    if ($compact) {
        $FullPanel.Visibility='Collapsed'; $MiniPanel.Visibility='Visible'; $ResizeGrip.Visibility='Collapsed'
        $window.Width=370; $window.Height=440; $ToggleButton.Content='Expand'
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
        if ($compact) { $window.Height=470 }
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
$script:quotaRows=@{}
$script:contextQuotaRows=@{}
function Update-ContextQuotaBars {
    $quota=Select-FreshQuota $shared.LiveQuota $shared.Latest.Tokens.Quota
    $entries=if ($quota) {@($quota.Windows)} else {@()}
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
        $observed=if ($entry.Observed) {$entry.Observed} else {$quota.Observed}; $stale=([DateTimeOffset]::Now-$observed).TotalMinutes -gt 2
        $row.Label.Text=('{0} | {1:N0}% used{2}' -f $period,(100-$entry.Remaining),$(if($stale){' *'}else{''}))
        $row.Bar.Value=$entry.Remaining
        $row.Panel.ToolTip="$($entry.Name)`n$(Format-QuotaReset $entry.Reset)`nObserved $($observed.ToLocalTime().ToString('MMM d HH:mm:ss'))$(if($stale){' (older reading)'})`n$($quota.Source)"
    }
    foreach ($key in @($script:contextQuotaRows.Keys)) {
        if ($key -notin $keys) { [void]$ContextQuotaBars.Children.Remove($script:contextQuotaRows[$key].Panel); $script:contextQuotaRows.Remove($key) }
    }
}
$script:tokenMetricRows=@{}; $script:tokenTaskRows=@{}
function Update-TokenPanel($tokens=$shared.Latest.Tokens) {
    $TokenLive.Text=if ($shared.Error) {'Read error'} else {'Watching files | 1 s'}
    $TokenLive.ToolTip=if ($shared.Error) {$shared.Error} else {'Reads new local usage records each second. Codex may write usage after a request ends.'}
    if ($tokens -and $tokens.Tasks) {
        $TokenTotal.Text=Format-TokenValue $tokens.Total
        $age=[Math]::Max(0,[int]([DateTimeOffset]::Now-$tokens.Observed).TotalSeconds)
        $TokenBreakdown.Text="$($tokens.Tasks) chats | Last record $($tokens.Observed.ToLocalTime().ToString('HH:mm:ss'))"
        if ($age -gt 120) { $TokenBreakdown.Text+=' | No recent usage' }
        $TokenCoverage.Text="Total = input + output.`nCache is part of input. Reasoning is part of output.`n-- means no value. * means partial data.`n$($tokens.Coverage)`nSubscription limits apply to the account. Token counts come from this device."
    } else { $TokenTotal.Text='--'; $TokenBreakdown.Text='Waiting for a usage record'; $TokenCoverage.Text='Counts appear when Codex writes a usage record. No estimate is added between records.' }
    $metricDefs=@(
        @('Input','Input','DetailedTasks','All input tokens, including cached input.'),
        @('Output','Output','DetailedTasks','All output tokens, including reasoning.'),
        @('Cache','Cached','CacheTasks','Input read from cache. Included in Input.'),
        @('Uncached','Uncached','CacheTasks','Input minus cached input.'),
        @('Reasoning','Reasoning','ReasoningTasks','Reasoning output. Included in Output.'),
        @('Cache hit','Hit','CacheTasks','Cached input divided by input for chats with both counters.')
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
            $title=New-Label '' 13 '#778DA9'; $detail=New-Label '' 11 '#E0E1DD'; $total=New-Label '' 25 '#E0E1DD'
            $brief=New-Label '' 11 '#778DA9'
            $expand=New-Object Windows.Controls.Expander; $expand.Header='Token and quota details'; $expand.Content=$detail; $expand.Margin='0,5,0,0'
            [void]$panel.Children.Add($title); [void]$panel.Children.Add($total); [void]$panel.Children.Add($brief); [void]$panel.Children.Add($expand); [void]$TokenTasks.Children.Add($panel)
            $script:tokenTaskRows[$key]=@{Panel=$panel;Title=$title;Total=$total;Detail=$detail;Brief=$brief;Expand=$expand}
        }
        $row=$script:tokenTaskRows[$key]
        $target=if ($chat.Active) {$ActiveTokenTasks} else {$TokenTasks}
        if ($row.Panel.Parent -ne $target) { [void]$row.Panel.Parent.Children.Remove($row.Panel); [void]$target.Children.Add($row.Panel) }
        $row.Total.Text="$(Format-TokenValue $chat.Total) tokens"
        $row.Total.ToolTip='Cumulative total for this chat, including earlier turns.'
        $status=if ($chat.Active) {'Running'} else {'Idle'}
        $row.Title.Text="$($chat.Title) | $status"
        $row.Brief.Text=if($chat.QuotaShare){$chat.QuotaShare}else{'Est. tracked share: 5h -- | 7d --'}
        $row.Brief.ToolTip=$chat.QuotaNotes
        $row.Detail.Text=Get-ChatTokenDetails $chat
        $row.Panel.ToolTip="Last model: $($chat.Model). Counts cover the whole chat, including earlier models. Last record: $(if ($chat.Observed) {$chat.Observed.ToLocalTime().ToString('HH:mm:ss')} else {'waiting'})."
    }
    foreach ($key in @($script:tokenTaskRows.Keys)) { if ($key -notin $keys) { [void]$script:tokenTaskRows[$key].Panel.Parent.Children.Remove($script:tokenTaskRows[$key].Panel); $script:tokenTaskRows.Remove($key) } }
    $quota=Select-FreshQuota $shared.LiveQuota $tokens.Quota
    $entries=@(); if ($quota) { $entries=@($quota.Windows) }
    $keys=@()
    $index=0
    foreach ($entry in $entries) {
        $key="$index/$($entry.Name)"; $keys+=$key; $index++
        if (-not $script:quotaRows.ContainsKey($key)) {
            $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='0,4,10,8'
            $label=New-Label '' 12 '#E0E1DD'; $bar=New-Object Windows.Controls.ProgressBar; $bar.Height=5; $bar.Maximum=100; $bar.Foreground='#778DA9'; $bar.Background='#415A77'
            $reset=New-Label '' 10 '#E0E1DD'
            [void]$panel.Children.Add($label); [void]$panel.Children.Add($bar); [void]$panel.Children.Add($reset)
            [void]$QuotaCards.Children.Add($panel); $script:quotaRows[$key]=@{Panel=$panel;Label=$label;Bar=$bar;Reset=$reset}
        }
        $row=$script:quotaRows[$key]; $observed=if ($entry.Observed) {$entry.Observed} else {$quota.Observed}; $period=if ($entry.Minutes -eq 300) {'5h'} elseif ($entry.Minutes -eq 10080) {'7d'} else {$entry.Name}; $row.Label.Text=('{0} | {1:N0}% used{2}' -f $period,(100-$entry.Remaining),$(if(([DateTimeOffset]::Now-$observed).TotalMinutes -gt 2){' *'}else{''})); $row.Bar.Value=100-$entry.Remaining; $row.Reset.Text=Format-QuotaReset $entry.Reset; $row.Reset.Visibility='Collapsed'; $row.Panel.ToolTip=$entry.Name+"`n"+$row.Reset.Text+"`nObserved $($observed.ToLocalTime().ToString('MMM d HH:mm:ss')) | $($quota.Source)"
    }
    foreach ($key in @($script:quotaRows.Keys)) { if ($key -notin $keys) { [void]$QuotaCards.Children.Remove($script:quotaRows[$key].Panel); $script:quotaRows.Remove($key) } }
    $SubscriptionHeading.Text=if ($quota.Plan) {"Account quota used | $($quota.Plan)"} else {'Account quota used'}
    $TokenSource.Text=if ($quota) { "$($quota.Source) | $($quota.Plan) | checked $($quota.Observed.ToLocalTime().ToString('MMM d HH:mm:ss'))" } else { 'No quota reading yet. Codex subscription sign-in required.' }
    if ($quota -and -not $entries.Count) { $TokenSource.Text+=' | No quota windows supplied.' }
    if ($quota -and $null -ne $quota.ResetCredits) { $TokenSource.Text+="`nAvailable reset credits: $($quota.ResetCredits) (read only)" }
    if ($shared.Fetching) { $TokenSource.Text+=' | Refreshing...' }
    elseif ($shared.QuotaError) { $TokenSource.Text+="`n$($shared.QuotaError)" }
    if ($quota -and ([DateTimeOffset]::Now-$quota.Observed).TotalMinutes -gt 2) { $TokenSource.Text+=' | STALE' }
    $RefreshUsage.Content=if ($shared.Fetching) {'Reading...'} elseif ($shared.QuotaError) {'Retry'} else {'Refresh'}; $RefreshUsage.ToolTip=if ($shared.QuotaError) {$shared.QuotaError} else {'Read current subscription limits'}
    $RefreshUsage.IsEnabled=-not $shared.Fetching
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
$ToggleButton.Add_Click({ Set-WidgetCompact (-not [bool]$prefs.Compact); Save-Preferences })
$MiniEditContext.Add_Click({
    $id=$script:displayedTask
    if (-not $id -or -not $script:cardControls.ContainsKey($id)) { return }
    $editor=$script:cardControls[$id].Editor
    if (-not $editor) { return }
    Set-WidgetMode 'Context'; Set-WidgetCompact $false
    $editor.IsExpanded=$true; $window.UpdateLayout(); $editor.BringIntoView(); Save-Preferences
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
        $MiniUsage.Text=if ($null -ne $lead.Percent) { '{0:N0} / {1:N0} tokens' -f $lead.Input,$lead.Window } else { 'Waiting for recorded usage' }
        $MiniPercent.Text=if ($null -ne $lead.Percent) { '{0:N1}%' -f $lead.Percent } else { '--' }
        $MiniRemaining.Text=if ($null -ne $lead.Input -and $lead.Window -gt 0) { '{0:N0}' -f [Math]::Max(0,$lead.Window-$lead.Input) } else { '--' }
        $MiniCompactions.Text=[string]$lead.Compactions
        $MiniCached.Text=if ($lead.Input -gt 0) { '{0:N0}%' -f (100*$lead.Cached/$lead.Input) } else { '--' }
        $MiniUpdated.Text="Last event $($lead.LastEvent)"
        $TaskPosition.Text=('{0} / {1}' -f (1+[array]::IndexOf($active,$lead)),$active.Count)
        $MiniBar.Value=[Math]::Max(0,[Math]::Min(100,[double]$lead.Percent))
        $MiniBar.Foreground=if ($lead.Status -eq 'COMPACTING') { '#778DA9' } elseif ($lead.Percent -ge 95) { '#778DA9' } elseif ($lead.Percent -ge 80) { '#778DA9' } else { '#778DA9' }
        $MiniPercent.Foreground=$MiniBar.Foreground
    } else {
        $MiniEditContext.IsEnabled=$false; $MiniTitle.Text='No running chats'; $MiniTitle.ToolTip=$null
        $MiniStatus.Text='Ready when you are'; $MiniBar.Value=0
        $MiniUsage.Text='Waiting for usage'; $MiniPercent.Text='--'
        $MiniRemaining.Text='--'; $MiniCompactions.Text='--'; $MiniCached.Text='--'
        $MiniUpdated.Text='Monitoring local chats'; $TaskPosition.Text='0 / 0'
    }
    $PreviousTask.IsEnabled=($active.Count -gt 1); $NextTask.IsEnabled=$PreviousTask.IsEnabled
    $ids=@($snapshot.Cards | ForEach-Object { $_.Id })
    foreach ($id in @($script:cardControls.Keys)) {
        if ($id -notin $ids) { [void]$Cards.Children.Remove($script:cardControls[$id].Border); $script:cardControls.Remove($id) }
    }
    if ($script:emptyLabel) { [void]$Cards.Children.Remove($script:emptyLabel); $script:emptyLabel=$null }
    if ($ids.Count -eq 0) {
        $script:emptyLabel=New-Label 'No running chats. Ready when you are.' 17 '#E0E1DD'
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
                $editor=New-InlineLimitsEditor $card.Cwd; $controls.Editor=$editor
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
        $c.Title.ToolTip="Initial: $($card.Initial)`nTask: $($card.Id)"
        $c.Model.Text="$($card.Model)"; $c.Model.ToolTip=$card.Cwd
        $c.Usage.Text=if ($null -ne $card.Percent) { '{0:N1}%   {1:N0} / {2:N0} tokens' -f $card.Percent,$card.Input,$card.Window } else { 'Waiting for token usage' }
        $c.Bar.Value=[Math]::Min(100,[Math]::Max(0,[double]$card.Percent)); $c.Bar.Foreground=$color
        $c.Saved.Text=''
        if ($card.Saved) {
            if ($card.Saved.Error) { $c.Saved.Text=$card.Saved.Error }
            else {
                $c.Saved.Text='Saved {0}: {1:N0} raw' -f $card.Saved.Source,$card.Saved.Requested
                if ($null -ne $card.Saved.Expected) {
                    $c.Saved.Text+=' -> {0:N0} usable' -f $card.Saved.Expected
                    $c.Saved.Text+=if ($card.Saved.Expected -eq $card.Window) { ' (matches)' } else { ' (not applied here)' }
                } else { $c.Saved.Text+=' (usable size unknown)' }
            }
        }
        $c.Saved.Foreground='#778DA9'
        $c.Details.Text="Compactions: $($card.Compactions)  |  Last event: $($card.LastEvent)`nCached: $('{0:N0}' -f $card.Cached)  |  Output: $('{0:N0}' -f $card.Output)"
        if ($card.Error) { $c.Details.Text+="`nRead error: $($card.Error)" }
    }
}
function Show-Overlay {
    if ($script:restoreTab) { $script:restoreTab.Hide() }
    $window.Show(); $window.WindowState='Normal'; [void]$window.Activate()
}
function Hide-Overlay([bool]$park=$false) {
    if ($park) {
        $workArea=Get-WidgetWorkArea
        $script:restoreTab.Left=$workArea.Right-$script:restoreTab.Width-12
        $script:restoreTab.Top=[Math]::Max($workArea.Top+12,[Math]::Min($window.Top,$workArea.Bottom-50))
        $script:restoreTab.Show()
    } else {
        $script:restoreTab.Hide()
        $tray.ShowBalloonTip(4000,'Context-Token Codex is running','Click the CTC icon beside the clock (or inside the ^ menu) to restore.',[Windows.Forms.ToolTipIcon]::Info)
    }
    $window.Hide()
}
function Update-CompactPercentageHint($form) {
    $example='Example: 90% of 200k = 180k. Percent needs an entered window. Saved as tokens. Reset: default.'
    try {
        $w=ConvertTo-TokenLimit $form.Window.Text $null; $c=ConvertTo-TokenLimit $form.Compact.Text $w.Limit
        if ($w.Limit -gt 0 -and $null -ne $c.Limit) {
            $form.Hint.Text=('{0:N1}% = {1:N0} tokens. ' -f (100.0*$c.Limit/$w.Limit),$c.Limit)+$example
        } else { $form.Hint.Text=$example }
    } catch { $form.Hint.Text=$example }
}
function Connect-CompactPercentageHint($windowField,$compactField,$hint) {
    $form=@{Window=$windowField;Compact=$compactField;Hint=$hint}
    foreach ($field in @($windowField,$compactField)) {
        $field.Tag=$form
        $field.Add_TextChanged({param($sender,$eventArgs) Update-CompactPercentageHint $sender.Tag})
    }
    Update-CompactPercentageHint $form
}
function New-InlineLimitsEditor([string]$project) {
    $expander=New-Object Windows.Controls.Expander; $expander.Header='Edit context limits'; $expander.Foreground='#E0E1DD'; $expander.Margin='0,8,0,0'
    $panel=New-Object Windows.Controls.StackPanel; $expander.Content=$panel
    $path=Join-Path $project '.codex/config.toml'
    [void]$panel.Children.Add((New-Label 'Project defaults for all models. Running chats may need a reload.' 10))
    $fields=@{}
    foreach ($spec in @(@('Window','Context window: e.g. 258400 or 1000k'),@('Compact','Compact at: e.g. 180k or 90%'))) {
        [void]$panel.Children.Add((New-Label $spec[1] 10))
        $input=New-Object Windows.Controls.TextBox; $input.Padding='8,6'; $input.Margin='0,3,0,6'
        $current=if ($spec[0] -eq 'Window') {Get-TopLevelContextWindow $path} else {Get-TopLevelAutoCompactLimit $path}
        $input.Text=if ($null -eq $current) {'default'} else {[string]$current}; $fields[$spec[0]]=$input; [void]$panel.Children.Add($input)
    }
    $hint=New-Label '' 10; [void]$panel.Children.Add($hint); Connect-CompactPercentageHint $fields.Window $fields.Compact $hint
    $result=New-Label '' 10
    $save=New-Object Windows.Controls.Button; $save.Content='Save project limits'; $save.Margin='0,5,0,5'
    $save.Tag=@{Path=$path;Window=$fields.Window;Compact=$fields.Compact;Result=$result}
    $save.Add_Click({param($sender,$eventArgs)
        $form=$sender.Tag
        try {
            $windowLimit=ConvertTo-TokenLimit $form.Window.Text $null; $compactLimit=ConvertTo-TokenLimit $form.Compact.Text $windowLimit.Limit
            [void](Set-ContextLimits $form.Path @{model_context_window=$windowLimit.Limit;model_auto_compact_token_limit=$compactLimit.Limit})
            $form.Result.Text='Saved for this project, all models. Reload may be required.'
        } catch { $form.Result.Text=$_.Exception.Message }
    })
    [void]$panel.Children.Add($save); [void]$panel.Children.Add($result); Apply-WidgetTheme $expander
    return $expander
}
function Show-Settings([string]$pane='Context') {
    $script:settings=@{}
    [xml]$settingsXaml=@'
<UserControl xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <DockPanel><DockPanel DockPanel.Dock="Top" Margin="0,0,0,10"><Button x:Name="BackTasks" Content="Back" HorizontalAlignment="Left" Padding="12,4"/></DockPanel><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="0,0,10,0"><StackPanel x:Name="AppearanceSettings">
  <TextBlock Text="Window &amp; startup" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,14"/>
  <TextBlock x:Name="OpacityLabel" Text="Background opacity"/>
  <Slider x:Name="OpacitySlider" Minimum="40" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" Margin="0,8,0,8"/>
  <TextBlock Text="40% opacity = more transparent; 100% = opaque. Text stays solid. Saves live." TextWrapping="Wrap" Foreground="#E0E1DD" Margin="0,0,0,12"/>
  <TextBlock Text="Corner placement (current screen)"/>
  <ComboBox x:Name="Corner" Margin="0,4,0,10"><ComboBoxItem Content="Free position"/><ComboBoxItem Content="Top left"/><ComboBoxItem Content="Top right"/><ComboBoxItem Content="Bottom left"/><ComboBoxItem Content="Bottom right"/></ComboBox>
  <Expander Header="Move and resize" Margin="0,0,0,12"><TextBlock Text="Drag the header to move; release near a corner to snap. Use Expand or Collapse to switch size. Drag the bottom-right grip to resize the full view." FontSize="11" TextWrapping="Wrap"/></Expander>
  <CheckBox x:Name="Auto" Content="Auto-open with app" ToolTip="Start the app watcher at Windows sign-in." Margin="0,0,0,10"/>
  <TextBlock Text="App to follow"/><ComboBox x:Name="Target" Margin="0,4,0,10"><ComboBoxItem Content="Codex"/><ComboBoxItem Content="ChatGPT"/><ComboBoxItem Content="Either"/></ComboBox>
  <TextBlock TextWrapping="Wrap" Foreground="#E0E1DD" Text="Overlay stays open after the app closes. Minimize uses the taskbar; Hide to tray keeps it available beside the clock. Close exits; auto-open can reopen it on the next app launch."/>
  <Button x:Name="SaveApp" Content="Save window preferences" Padding="10" Margin="0,12,0,20"/>
  </StackPanel><StackPanel x:Name="ContextSettings">
  <TextBlock Text="Context limits" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,12"/>
  <TextBlock Text="Save to"/><ComboBox x:Name="Scope" MinHeight="32" Margin="0,4,0,10"/>
  <Border BorderBrush="#778DA9" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,12"><TextBlock x:Name="Current" FontSize="11" TextWrapping="Wrap"/></Border>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <StackPanel><TextBlock Text="Context window (all models)"/><TextBox x:Name="Context" Padding="8,6" MinHeight="34" Margin="0,4,0,0" ToolTip="Raw token count. Use a number or default."/></StackPanel>
   <StackPanel Grid.Column="2"><TextBlock Text="Compact at"/><TextBox x:Name="Compact" Padding="8,6" MinHeight="34" Margin="0,4,0,0" ToolTip="Use tokens, 90% of the entered context window, or default. Percent is saved as tokens."/></StackPanel>
  </Grid>
  <TextBlock Text="Tokens: 180000 = 180k | 1000000 = 1000k" FontSize="10" Opacity="0.8" Margin="0,6,0,10"/>
  <TextBlock x:Name="CompactHint" FontSize="10" Margin="0,0,0,10"/><TextBlock Text="Saved limits may need a chat reload." FontSize="11" Foreground="#778DA9" Margin="0,0,0,10"/>
  <Button x:Name="SaveLimits" Content="Save limits" HorizontalAlignment="Right" MinWidth="120" Padding="12,6" Margin="0,0,0,12"/>
  <Expander Header="How limits work" Foreground="#E0E1DD"><TextBlock Text="The window is a raw token count. Live chats report usable capacity. A saved value does not change a running chat or increase model capacity. Use default to remove this scope's override. Compact at accepts 90% when a context window is entered. Percent is converted to tokens on save; it does not track future window changes. Hover over the saved values to see the file and inherited settings." FontSize="11" Margin="0,8,0,8" TextWrapping="Wrap"/></Expander>
  </StackPanel><TextBlock x:Name="Result" TextWrapping="Wrap" Foreground="#778DA9"/>
 </StackPanel></ScrollViewer></DockPanel>
</UserControl>
'@
    $script:settings.dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($settingsXaml))
    $script:settings.auto=$script:settings.dialog.FindName('Auto'); $script:settings.target=$script:settings.dialog.FindName('Target'); $script:settings.scope=$script:settings.dialog.FindName('Scope')
    $script:settings.current=$script:settings.dialog.FindName('Current'); $script:settings.context=$script:settings.dialog.FindName('Context'); $script:settings.compact=$script:settings.dialog.FindName('Compact'); $script:settings.result=$script:settings.dialog.FindName('Result')
    Connect-CompactPercentageHint $script:settings.context $script:settings.compact ($script:settings.dialog.FindName('CompactHint'))
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
            $raw=Get-TopLevelContextWindow $choice.Path; $threshold=Get-TopLevelAutoCompactLimit $choice.Path
            $script:settings.context.Text=if ($null -eq $raw) { 'default' } else { [string]$raw }
            $script:settings.compact.Text=if ($null -eq $threshold) { 'default' } else { [string]$threshold }
            $script:settings.current.Text="File: $($choice.Path)`nSaved raw window: $(Format-Limit $raw)`nSaved threshold: $(Format-Limit $threshold)"
            if ($choice.Card) {
                $script:settings.current.Text+="`nLive usable window: $(Format-Limit $choice.Card.Window) | $($choice.Card.Model)"
                $script:settings.current.Text+="`nGlobal fallback window: $(Format-Limit (Get-TopLevelContextWindow $script:configPath))"
                $script:settings.current.Text+="`nGlobal fallback threshold: $(Format-Limit (Get-TopLevelAutoCompactLimit $script:configPath))"
            }
            $compactScope=Get-TopLevelAutoCompactScope $choice.Path
            if (-not $compactScope) { $compactScope=Get-TopLevelAutoCompactScope $script:configPath }
            if (-not $compactScope) { $compactScope='total (default)' }
            $script:settings.current.Text+="`nCompaction accounting: $compactScope"
            $script:settings.current.ToolTip=$script:settings.current.Text
            $script:settings.current.Text="Saved window: $(Format-Limit $raw) | Compact: $(Format-Limit $threshold)"
            if ($choice.Card) { $script:settings.current.Text+="`nLive: $(Format-Limit $choice.Card.Window) | $($choice.Card.Model)" }
            $script:settings.result.Text=''
        } catch { $script:settings.result.Text=$_.Exception.Message }
    })
    $script:settings.scope.SelectedIndex=0
    $script:settings.dialog.FindName('SaveLimits').Add_Click({
        try {
            if ($script:coreError) { throw $script:coreError }
            $newContext=ConvertTo-TokenLimit $script:settings.context.Text $null; $newCompact=ConvertTo-TokenLimit $script:settings.compact.Text $newContext.Limit
            [void](Set-ContextLimits $script:settings.scope.SelectedItem.Path @{model_context_window=$newContext.Limit;model_auto_compact_token_limit=$newCompact.Limit})
            $script:settings.result.Foreground='#778DA9'; $script:settings.result.Text="Saved. Backup created. Reload may be required."
            $script:settings.current.Text="Saved window: $(Format-Limit $newContext.Limit) | Compact: $(Format-Limit $newCompact.Limit)"
            $script:settings.current.ToolTip="File: $($script:settings.scope.SelectedItem.Path)`n$($script:settings.current.Text)"
            if ($script:settings.scope.SelectedItem.Card) { $script:settings.current.Text+="`nLive: $(Format-Limit $script:settings.scope.SelectedItem.Card.Window) | $($script:settings.scope.SelectedItem.Card.Model)" }
        } catch { $script:settings.result.Tag='Error'; $script:settings.result.Foreground='#778DA9'; $script:settings.result.Text=$_.Exception.Message }
    })
    $script:settings.dialog.FindName('SaveApp').Add_Click({
        try {
            Set-OverlayStartup ([bool]$script:settings.auto.IsChecked) $script:folder
            $prefs.AutoOpen=[bool]$script:settings.auto.IsChecked; $prefs.Target=[string]$script:settings.target.SelectedItem.Content; Save-Preferences
            if ($prefs.AutoOpen) { Start-Watcher }
            $script:settings.result.Foreground='#778DA9'; $script:settings.result.Text='Window preferences saved. Startup applies to your Windows account only.'
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
        Set-WidgetCompact $false
    $FullPanel.Visibility='Collapsed'; $TokensPanel.Visibility='Collapsed'
    $SettingsHost.Content=$script:settings.dialog; $SettingsHost.Visibility='Visible'
    $LimitsMode.Tag=if ($pane -eq 'Context') {'Selected'} else {''}; $ContextMode.Tag=''; $TokenMode.Tag=''
    Apply-WidgetTheme $script:settings.dialog
    $script:settings.dialog.FindName('AppearanceSettings').Visibility=if ($pane -eq 'Widget') {'Visible'} else {'Collapsed'}
    $script:settings.dialog.FindName('ContextSettings').Visibility=if ($pane -eq 'Context') {'Visible'} else {'Collapsed'}
    $script:settings.dialog.FindName('BackTasks').Add_Click({ Set-WidgetCompact $false })
}
function Start-Watcher {
    $watchScript=Join-Path $script:folder 'Watch-App.ps1'
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$watchScript+'"')
}
$script:tray=New-Object Windows.Forms.NotifyIcon
$script:trayIcon=New-Object Drawing.Icon((Join-Path $script:folder 'Context.ico'))
$tray.Icon=$script:trayIcon; $tray.Text='CTC - click to restore'; $tray.Visible=$true
[xml]$tabXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Restore Context-Token Codex" Width="156" Height="38" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True"><Border CornerRadius="12" Background="#0D1B2A" BorderBrush="#778DA9" BorderThickness="1"><TextBlock Text="CTC   Restore  &#x203A;" Foreground="#778DA9" FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Center" Cursor="Hand" ToolTip="Click to restore the context widget"/></Border></Window>
'@
$script:restoreTab=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($tabXaml))
$restoreTab.Add_MouseLeftButtonUp({ Show-Overlay })
$menu=New-Object Windows.Forms.ContextMenuStrip
$restore=$menu.Items.Add('Show overlay'); $restore.Add_Click({ Show-Overlay })
$hide=$menu.Items.Add('Hide to notification area'); $hide.Add_Click({ Hide-Overlay $false })
$settingsItem=$menu.Items.Add('Settings'); $settingsItem.Add_Click({ Show-Overlay; Show-Settings })
$exitItem=$menu.Items.Add('Exit'); $exitItem.Add_Click({ $window.Close() })
$tray.ContextMenuStrip=$menu
$tray.Add_MouseClick({ param($sender,$eventArgs) if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) { Show-Overlay } })
$DirectTray.Add_Click({ Hide-Overlay $false }); $TrayButton.Add_Click({ Hide-Overlay $true }); $ParkButton.Add_Click({ Hide-Overlay $true }); $SettingsButton.Add_Click({ Show-Settings })
$QuickSettings.Add_Click({ Show-Settings 'Widget' }); $QuickContext.Add_Click({ Show-Settings 'Context' })
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
                if ($prefs.Compact -or -not $script:cardControls[$script:displayedTask].Editor.IsExpanded -or $prefs.Mode -ne 'Context') { throw 'Mini context shortcut failed.' }
                $inline=New-InlineLimitsEditor $CodexHome
                $inlineSave=@($inline.Content.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0]
                $inlineSave.Tag.Window.Text='200k'; $inlineSave.Tag.Compact.Text='90%'
                if ($inlineSave.Tag.Compact.Tag.Hint.Text -notlike (('{0:N1}%' -f 90.0)+'*')) { throw 'Compact percentage example did not update.' }
                $inlineSave.Tag.Window.Text='1000k'
                $inlineSave.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ((Get-TopLevelContextWindow $inlineSave.Tag.Path) -ne 1000000 -or (Get-TopLevelAutoCompactLimit $inlineSave.Tag.Path) -ne 900000) { throw 'Inline chat limit edit failed.' }
                $LimitsMode.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ($SettingsHost.Visibility -ne 'Visible' -or $SettingsHost.Content -isnot [Windows.Controls.UserControl]) { throw 'Settings did not open inside the overlay.' }
                # Exercise handlers after Show-Settings has returned (no modal local scope).
                $script:settings.context.Text='500k'; $script:settings.compact.Text='36%'
                $script:settings.dialog.FindName('SaveLimits').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                if ((Get-TopLevelContextWindow $script:settings.scope.SelectedItem.Path) -ne 500000) { throw 'Embedded settings save failed after return.' }
                if ($TestReport) {
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
            $buttonBottom=$MiniEditContext.TranslatePoint([Windows.Point]::new(0,$MiniEditContext.ActualHeight),$MiniPanel).Y
            if ($buttonBottom -gt $MiniPanel.ActualHeight) { throw 'Mini context button is clipped.' }
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
            if ($script:contextQuotaRows.Count -ne 2 -or @($script:contextQuotaRows.Values | Where-Object {$_.Bar.Value -eq 65}).Count -ne 1) { throw 'Context quota bars failed.' }
            if ($TokensPanel.Visibility -ne 'Visible' -or $prefs.Mode -ne 'Tokens' -or $script:quotaRows.Count -ne 2) { throw 'Tokens mode switch or quota rendering failed.' }
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
    $shared.Stop=$true; $worker.Stop(); $worker.Dispose(); $quotaWorker.Stop(); $quotaWorker.Dispose(); $showEvent.Dispose()
    if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose()
}
if ($TestSeconds -gt 0 -and -not $script:testPassed) { exit 1 }
