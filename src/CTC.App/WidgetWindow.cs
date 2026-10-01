// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CTC.Core;
using static CTC.App.Controls;
using Forms=System.Windows.Forms;

namespace CTC.App;

public sealed partial class WidgetWindow:Window
{
    private readonly string home,data,prefsPath;
    private readonly Host host;
    private readonly Preferences prefs;
    private readonly QueueStore queue;
    private readonly RestartController restart;
    private readonly Forms.NotifyIcon tray;
    private readonly Window mainLayout,parkLayout;
    private readonly Border frame,parkFrame;
    private readonly Grid shell;
    private readonly System.Windows.Controls.Primitives.UniformGrid quotas;
    private readonly ContentControl body;
    private readonly TextBlock title,position,context,tokens,status;
    private readonly ProgressBar contextBar;
    private readonly Button previous,next;
    private readonly WrapPanel tabs;
    private readonly Grid appearance;
    private readonly Dictionary<string,bool> expanded=new();
    private ChatView[] chats=[];
    private ChatView? selected;
    private string selectedId="",page="Context",signature="",quotaSignature="";
    private long shownRevision=-1;
    private bool parked,large,closing,dragging,applyingSize;
    private Point returnPoint;
    private string returnCorner;
    private LimitEditor? editor;
    private MonitorSnapshot? snapshot;
    private readonly string[] args;

    public WidgetWindow(string home,string data,string[] args)
    {
        this.home=home;this.data=data;this.args=args;prefsPath=Path.Combine(data,"overlay.json");prefs=Preferences.Load(prefsPath);
        host=new(home,data,Array.IndexOf(args,"--ui-test")>=0);queue=new(Path.Combine(data,"limits-queue.json"),home);restart=new(Path.Combine(data,"restart.json"));
        parked=prefs.StartParked;large=!prefs.Compact;returnCorner=prefs.Corner;returnPoint=new(prefs.Left,prefs.Top);page=prefs.Mode;
        Title="Context-Token Codex";FontFamily=new FontFamily("Segoe UI");FontSize=12;Foreground=Text;
        WindowStyle=WindowStyle.None;AllowsTransparency=true;Background=Brushes.Transparent;ResizeMode=ResizeMode.NoResize;Topmost=prefs.Topmost;
        Icon=BitmapFrame.Create(new Uri("pack://application:,,,/ContextTokenCodex;component/Assets/Context.ico"));
        UseLayoutRounding=true;SnapsToDevicePixels=true;
        mainLayout=LegacyLayouts.Load<Window>("Main");parkLayout=LegacyLayouts.Load<Window>("Parked");
        frame=(Border)mainLayout.Content;mainLayout.Content=null;parkFrame=(Border)parkLayout.Content;parkLayout.Content=null;
        shell=(Grid)frame.Child;body=Main<ContentControl>("SettingsHost");
        title=Main<TextBlock>("MiniTitle");position=Main<TextBlock>("TaskPosition");context=Main<TextBlock>("MiniPercent");
        tokens=Park<TextBlock>("ParkTokens");status=Main<TextBlock>("MiniUpdated");contextBar=Main<ProgressBar>("MiniBar");
        quotas=Main<System.Windows.Controls.Primitives.UniformGrid>("ContextQuotaBars");
        tabs=(WrapPanel)Main<Button>("ContextMode").Parent;appearance=Main<Grid>("AppearanceControls");
        previous=Main<Button>("PreviousTask");next=Main<Button>("NextTask");
        Bind(previous,()=>Navigate(-1),"PreviousChat");Bind(next,()=>Navigate(1),"NextChat");
        Bind(Park<Button>("ParkPrevious"),()=>Navigate(-1),"ParkPrevious");Bind(Park<Button>("ParkNext"),()=>Navigate(1),"ParkNext");
        Bind(Park<Button>("ParkRestore"),()=>SetParked(false),"RestoreBar");
        foreach(string name in new[]{"ParkPrevious","ParkNext","ParkRestore"}){var b=Park<Button>(name);b.Width=24;b.Height=22;b.Padding=new Thickness(0);b.Margin=new Thickness(3,0,0,0);}
        Bind(Main<Button>("ToggleButton"),ToggleSize,"Expand");Bind(Main<Button>("DirectTray"),HideToTray,"Tray");
        Bind(Main<Button>("MinimizeButton"),()=>SetParked(true),"Minimize");Bind(Main<Button>("CloseButton"),Close,"CloseWidget");
        Bind(Main<Button>("QuickSettings"),ShowAppearance,"AppSettings");Bind(Main<Button>("QuickCorner"),CycleCorner,"Corner");
        Bind(Main<Button>("QuickPin"),()=>{Topmost=!Topmost;Main<Button>("QuickPin").Content=Topmost?"Pinned":"Pin on top";SavePreferences();},"Pin");
        Main<Button>("QuickPin").Content=Topmost?"Pinned":"Pin on top";
        Bind(Main<Button>("MiniEditContext"),()=>ShowPage("Limits"),"EditContextLimits");
        Bind(Main<Button>("ContextMode"),()=>ShowPage("Context"),"ContextMode");Bind(Main<Button>("TokenMode"),()=>ShowPage("Tokens"),"TokensMode");
        Bind(Main<Button>("LimitsMode"),()=>ShowPage("Limits"),"LimitsMode");Bind(Main<Button>("QueueMode"),()=>ShowPage("Queue"),"QueueMode");
        Bind(Main<Button>("RefreshUsage"),()=>_=host.Refresh(),"RefreshQuotas");
        Main<System.Windows.Documents.Hyperlink>("UserWebsite").RequestNavigate+=(_,e)=>{OpenUrl("https://yahyanabil.com");e.Handled=true;};
        Main<Grid>("DragHandle").MouseLeftButtonDown+=DragHeader;parkFrame.MouseLeftButtonDown+=DragHeader;
        title.MouseLeftButtonUp+=(_,_)=>{if(!large)ToggleSize();};
        var opacity=Main<Slider>("LiveOpacity");opacity.Value=prefs.Opacity*100;AutomationProperties.SetAutomationId(opacity,"BackgroundOpacity");
        opacity.ValueChanged+=(_,_)=>{prefs.Opacity=opacity.Value/100;SetOpacity(prefs.Opacity);Main<TextBlock>("LiveOpacityLabel").Text=$"{opacity.Value:0}%";SavePreferences();};
        Main<TextBlock>("LiveOpacityLabel").Text=$"{opacity.Value:0}%";
        Main<System.Windows.Controls.Primitives.Thumb>("ResizeGrip").DragDelta+=(_,e)=>{Width=Math.Max(360,Width+e.HorizontalChange);Height=Math.Max(520,Height+e.VerticalChange);prefs.Width=Width;prefs.Height=Height;SavePreferences();};
        SetOpacity(prefs.Opacity);UpdateLogo();DpiChanged+=(_,_)=>UpdateLogo();
        tray=new Forms.NotifyIcon{Text="CTC - select to restore",Visible=true};
        using(var stream=Application.GetResourceStream(new Uri("/ContextTokenCodex;component/Assets/Context.ico",UriKind.Relative))!.Stream)tray.Icon=new System.Drawing.Icon(stream);
        var menu=new Forms.ContextMenuStrip();menu.Items.Add("Show overlay",null,(_,_)=>Restore());menu.Items.Add("Hide to notification area",null,(_,_)=>HideToTray());menu.Items.Add("Settings",null,(_,_)=>{Restore();ShowAppearance();});menu.Items.Add("Exit",null,(_,_)=>Close());tray.ContextMenuStrip=menu;tray.DoubleClick+=(_,_)=>Restore();
        host.Changed+=()=>{if(!closing)Dispatcher.BeginInvoke(Update);};
        StateChanged+=(_,_)=>{if(WindowState==WindowState.Minimized){WindowState=WindowState.Normal;SetParked(true);}};
        SizeChanged+=(_,_)=>{if(IsLoaded&&large&&!parked&&!applyingSize){prefs.Width=Math.Max(360,ActualWidth);prefs.Height=Math.Max(520,ActualHeight);SavePreferences();}};
        Loaded+=async(_,_)=>{ApplySize();Place(returnCorner,returnPoint,true);if(Array.IndexOf(args,"--ui-test")>=0)_=UiChecks.Run(this,home,data,Program.Option(args,"--ui-test"));await Start();};
        Closing+=(_,_)=>{SavePreferences();closing=true;AtomicFile.Write(Path.Combine(data,"manual-close.txt"),DateTimeOffset.Now.ToString("o"));tray.Visible=false;tray.Dispose();host.Dispose();};
        ShowPage(page,false);ApplySize();
    }
    private async Task Start()
    {
        _=host.Start();
        string seconds=Program.Option(args,"--exit-after");
        if(double.TryParse(seconds,out double n)){await Task.Delay(TimeSpan.FromSeconds(n));Close();}
    }
    private T Main<T>(string name) where T:class=>(T)mainLayout.FindName(name);
    private T Park<T>(string name) where T:class=>(T)parkLayout.FindName(name);
    private static void Bind(Button b,Action action,string id){b.Click+=(_,_)=>action();AutomationProperties.SetAutomationId(b,id);}
    private void UpdateLogo()
    {
        var icon=Main<System.Windows.Controls.Image>("BrandIcon");var dpi=VisualTreeHelper.GetDpi(this);
        var decoder=BitmapDecoder.Create(new Uri("pack://application:,,,/ContextTokenCodex;component/Assets/Context.ico"),BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.OnLoad);
        icon.Source=decoder.Frames.OrderBy(x=>x.PixelWidth).FirstOrDefault(x=>x.PixelWidth>=32*dpi.DpiScaleX)??decoder.Frames.OrderBy(x=>x.PixelWidth).Last();RenderOptions.SetBitmapScalingMode(icon,BitmapScalingMode.HighQuality);
    }
    private void DragHeader(object sender,MouseButtonEventArgs e)
    {
        var origin=e.OriginalSource as DependencyObject;
        while(origin!=null){if(origin is Button)return;origin=VisualTreeHelper.GetParent(origin);}
        if(e.ChangedButton!=MouseButton.Left)return;
        dragging=true;try{DragMove();}finally{dragging=false;}
        var dpi=Dpi();var area=Forms.Screen.FromPoint(new System.Drawing.Point((int)(Left*dpi.X),(int)(Top*dpi.Y))).WorkingArea;
        double right=area.Right/dpi.X-Width,bottom=area.Bottom/dpi.Y-Height;
        bool leftNear=Math.Abs(Left-area.Left/dpi.X)<48,rightNear=Math.Abs(Left-right)<48,topNear=Math.Abs(Top-area.Top/dpi.Y)<48,bottomNear=Math.Abs(Top-bottom)<48;
        prefs.Corner=(leftNear||rightNear)&&(topNear||bottomNear)?(topNear?"Top":"Bottom")+(leftNear?"Left":"Right"):"Free";
        Place(prefs.Corner,new(Left,Top));if(!large||parked){returnCorner=prefs.Corner;returnPoint=new(Left,Top);}SavePreferences();
    }
    private void SetOpacity(double value){frame.Background.Opacity=value;parkFrame.Background.Opacity=value;}
    private void SavePreferences()
    {
        if(closing)return;
        prefs.Mode=page=="Tokens"?"Tokens":"Context";prefs.Compact=!large;prefs.Topmost=Topmost;
        // StartParked is the launch preference. Minimize does not change it.
        if((!large||parked)&&double.IsFinite(Left)&&double.IsFinite(Top)){prefs.Left=Left;prefs.Top=Top;}
        try{AtomicFile.Json(prefsPath,prefs);}catch(IOException e){status.Text=e.Message;}
    }
    public void Restore(){if(parked)SetParked(false);Show();ShowInTaskbar=true;WindowState=WindowState.Normal;Activate();}
    private void HideToTray(){Hide();ShowInTaskbar=false;tray.ShowBalloonTip(2500,"Context-Token Codex","CTC is in the Windows notification area.",Forms.ToolTipIcon.Info);}
    private void ToggleSize()
    {
        if(parked){SetParked(false);return;}
        if(!large){returnPoint=new(Left,Top);returnCorner=prefs.Corner;}
        large=!large;ApplySize();if(!large){prefs.Corner=returnCorner;Place(returnCorner,returnPoint,true);}else Place(prefs.Corner,new(Left,Top));
        SavePreferences();Render(true);
    }
    private void SetParked(bool value)
    {
        if(value&&!parked&&!large){returnPoint=new(Left,Top);returnCorner=prefs.Corner;}
        parked=value;ApplySize();Place(returnCorner,returnPoint,true);SavePreferences();Render(true);
    }
    private void ApplySize()
    {
        applyingSize=true;
        MinWidth=parked?0:300;MinHeight=parked?0:150;ResizeMode=ResizeMode.NoResize;
        Content=parked?parkFrame:frame;Width=parked?370:large?Math.Max(360,prefs.Width):370;
        Height=parked?88:large?Math.Max(520,prefs.Height):480;ShowInTaskbar=!parked;
        bool contextView=page=="Context";
        Main<StackPanel>("MiniPanel").Visibility=!parked&&contextView&&!large?Visibility.Visible:Visibility.Collapsed;
        Main<DockPanel>("FullPanel").Visibility=!parked&&contextView&&large?Visibility.Visible:Visibility.Collapsed;
        Main<ScrollViewer>("TokensPanel").Visibility=!parked&&page=="Tokens"?Visibility.Visible:Visibility.Collapsed;
        body.Visibility=!parked&&page is "Limits" or "Queue" or "Appearance"?Visibility.Visible:Visibility.Collapsed;
        appearance.Visibility=page is "Limits" or "Queue" or "Appearance"?Visibility.Collapsed:Visibility.Visible;
        Main<TextBlock>("AuthorLine").Visibility=large?Visibility.Visible:Visibility.Collapsed;
        Main<System.Windows.Controls.Primitives.Thumb>("ResizeGrip").Visibility=large&&!parked?Visibility.Visible:Visibility.Collapsed;
        Main<Button>("ToggleButton").Content=large?"Collapse":"Expand";
        Main<Button>("LimitsMode").Visibility=Main<Button>("QueueMode").Visibility=page=="Tokens"?Visibility.Collapsed:Visibility.Visible;
        quotaSignature="";UpdateQuotas();applyingSize=false;
    }
    private void Place(string corner,Point free,bool anchor=false)
    {
        // Use the current monitor. WinForms coordinates are physical pixels; WPF uses device-independent units.
        var point=anchor?free:new Point(Left,Top);var screen=Forms.Screen.FromPoint(new System.Drawing.Point((int)(point.X*Dpi().X),(int)(point.Y*Dpi().Y)));
        var work=screen.WorkingArea;var dpi=Dpi();double l=work.Left/dpi.X,t=work.Top/dpi.Y,w=work.Width/dpi.X,h=work.Height/dpi.Y;
        Left=corner.Contains("Right")?l+w-Width-12:corner.Contains("Left")?l+12:Math.Clamp(free.X,l,l+Math.Max(0,w-Width));
        Top=corner.Contains("Bottom")?t+h-Height-12:corner.Contains("Top")?t+12:Math.Clamp(free.Y,t,t+Math.Max(0,h-Height));
    }
    private (double X,double Y) Dpi(){var d=VisualTreeHelper.GetDpi(this);return(d.DpiScaleX,d.DpiScaleY);}
    private void CycleCorner()
    {
        var menu=new ContextMenu();
        foreach(var pair in new[]{("Top left","TopLeft"),("Top right","TopRight"),("Bottom left","BottomLeft"),("Bottom right","BottomRight")})
        {var item=new MenuItem{Header=pair.Item1};item.Click+=(_,_)=>{prefs.Corner=pair.Item2;returnCorner=prefs.Corner;Place(returnCorner,returnPoint,true);returnPoint=new(Left,Top);SavePreferences();};menu.Items.Add(item);}
        menu.PlacementTarget=Main<Button>("QuickCorner");menu.IsOpen=true;
    }
    private void Navigate(int delta)
    {if(chats.Length==0)return;int i=Array.FindIndex(chats,x=>x.Id==selectedId);selectedId=chats[(i+delta+chats.Length)%chats.Length].Id;shownRevision=-1;Update();}
    private void ShowPage(string name,bool unpark=true)
    {
        if(unpark&&parked){parked=false;large=false;ApplySize();Place(returnCorner,returnPoint,true);}
        if(name!=page)editor=null;page=name;ApplySize();if(IsLoaded&&!large)Place(returnCorner,returnPoint,true);Render(true);SavePreferences();
    }
    private void Update()
    {
        if(closing||dragging)return;snapshot=host.Snapshot;if(snapshot==null)return;
        var active=snapshot.ActiveChats;chats=active;
        selected=chats.FirstOrDefault(x=>x.Id==selectedId)??chats.FirstOrDefault();selectedId=selected?.Id??"";
        title.Text=selected?.Title??"No running chats";title.ToolTip=selected?.Initial;
        Main<TextBlock>("MiniStatus").Text=selected==null?"No active chats":$"{snapshot.ActiveChats.Length} active | {selected.Status.ToUpperInvariant()} | {selected.Model}";
        if(selected?.ContextPercent>=95)Main<TextBlock>("MiniStatus").Text+=" | CRITICAL";else if(selected?.ContextPercent>=80)Main<TextBlock>("MiniStatus").Text+=" | HIGH";
        position.Text=chats.Length>0?$"{Array.IndexOf(chats,selected!)+1} / {chats.Length}":"0 / 0";
        previous.IsEnabled=next.IsEnabled=Park<Button>("ParkPrevious").IsEnabled=Park<Button>("ParkNext").IsEnabled=chats.Length>1;
        context.Text=selected?.ContextPercent is {} percent?$"{percent:N1}%":"--";contextBar.Value=Math.Clamp(selected?.ContextPercent??0,0,100);
        Main<TextBlock>("MiniUsage").Text=selected?.ContextPercent!=null?$"{Format.Tokens(selected.Latest.Input)} / {Format.Tokens(selected.Window)} tokens":"No usage record";
        Main<TextBlock>("MiniRemaining").Text=selected?.Window>0&&selected.Latest.Input is {} input?Format.Tokens(Math.Max(0,selected.Window.Value-input)):"--";
        Main<TextBlock>("MiniCompactions").Text=selected?.Compactions.ToString()??"--";
        Main<TextBlock>("MiniCached").Text=selected?.Latest.CacheRate is {} hit?$"{hit:N0}%":"--";
        Main<Button>("MiniEditContext").IsEnabled=selected?.Cwd.Length>0;
        Park<TextBlock>("ParkTitle").Text=selected?.Title??"No active chats";
        Park<TextBlock>("ParkTitle").ToolTip=selected?.Title;
        Park<TextBlock>("ParkContext").Text=selected?.ContextPercent is {} cp?$"Context {cp:N1}%":"Context --";
        tokens.Text="Tokens "+Format.Short(selected?.Total.Total);tokens.ToolTip=Format.Tokens(selected?.Total.Total)+" tokens";
        context.ToolTip=selected==null?"No context record.":$"{Format.Tokens(selected.Latest.Input)} / {Format.Tokens(selected.Window)} tokens";
        status.Text=selected==null?"Monitoring local chats":"Last event "+selected.LastEvent.ToLocalTime().ToString("HH:mm:ss");
        Main<TextBlock>("Health").Text=host.Error.Length>0?host.Error:snapshot.Warning.Length>0?snapshot.Warning:snapshot.CompactionSource;
        UpdateQuotas();
        Render(false);
    }
    private void UpdateQuotas()
    {
        var q=host.Quota;bool stale=q!=null&&DateTimeOffset.Now-q.Observed>TimeSpan.FromMinutes(2);
        string sig=q==null?"none":JsonSerializer.Serialize(q.Windows)+q.Observed+stale;
        if(sig==quotaSignature)return;quotaSignature=sig;quotas.Children.Clear();
        var windows=q?.Windows??[];quotas.Columns=windows.Length==1?1:2;
        if(windows.Length==0){quotas.Columns=1;var panel=new StackPanel{Margin=new Thickness(0,0,10,4)};panel.Children.Add(Label("Account quota | --",10));panel.Children.Add(new ProgressBar{Maximum=100,Value=0,Height=5,Margin=new Thickness(0,3,0,0)});quotas.Children.Add(panel);Park<TextBlock>("ParkQuota").Text="Quota --";return;}
        foreach(var w in windows)
        {
            var p=new StackPanel{Margin=new Thickness(0,0,10,4)};
            p.Children.Add(Label(w.Label+" | "+$"{w.Remaining:N0}%"+" left"+(stale?" *":""),10));
            p.Children.Add(new ProgressBar{Maximum=100,Value=w.Remaining,Height=5,Margin=new Thickness(0,3,0,0)});
            p.ToolTip=$"{q!.Plan} | {w.Bucket}\n{Format.Percent(w.Used)} used\nReset: {w.Reset?.ToLocalTime().ToString("g")??"--"}\nObserved: {q.Observed.ToLocalTime():g}"+(stale?"\nThe reading is old. Select Refresh.":"");quotas.Children.Add(p);
        }
        Park<TextBlock>("ParkQuota").Text=string.Join("  |  ",windows.Select(w=>$"{w.Label} {w.Remaining:N0}% left"));
        Park<TextBlock>("ParkQuota").ToolTip=$"Quota checked: {q!.Observed.ToLocalTime():HH:mm:ss}";
    }
    private void Render(bool force)
    {
        foreach(Button b in tabs.Children)b.Tag=(string)b.Content==page?"Selected":"";
        if(parked)return;
        if(page=="Limits")
        {
            if(editor==null){editor=new(home,queue,()=>selected,snapshot?.Projects??[],()=>ShowPage("Context"));body.Content=editor.View;}
            return;
        }
        if(page=="Queue"){RenderQueue(force);return;}
        if(page=="Appearance"){if(force)RenderAppearance();return;}
        string nextSignature=selectedId+page+quotaSignature+string.Join("|",(snapshot?.Chats??[]).Select(c=>c.Id+":"+c.Revision));
        if(!force&&signature==nextSignature)return;signature=nextSignature;shownRevision=selected?.Revision??-1;
        CaptureExpanded(Main<ScrollViewer>("TokensPanel"));CaptureExpanded(Main<StackPanel>("Cards"));
        if(page=="Tokens")RenderTokens();else if(large)RenderContextCards();
    }
    private void ShowAppearance()=>ShowPage("Appearance");
    private void SetAuto(bool enabled){prefs.AutoOpen=enabled;SavePreferences();try{Installer.SetStartup(AppContext.BaseDirectory,data,enabled);if(enabled)Installer.StartWatcher(AppContext.BaseDirectory,data);}catch(Exception e) when(e is IOException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException){status.Text=e.Message;}}
    private void ShowQueue()=>ShowPage("Queue");
    private void RenderQueue(bool force)
    {
        string sig="";
        QueueView[] views;
        try{views=queue.Views(snapshot?.Chats??[]);sig=JsonSerializer.Serialize(views)+JsonSerializer.Serialize(restart.Read())+(snapshot==null?"":RestartGate.Reason(snapshot));}
        catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException){body.Content=Label(e.Message);return;}
        if(!force&&signature==sig)return;signature=sig;
        var dock=new DockPanel();var p=new StackPanel();DockPanel.SetDock(p,Dock.Top);dock.Children.Add(p);p.Children.Add(Label("Queue",18));
        var pending=Label(views.Length>0?"Limits updates in queue":"No limits updates in queue",11);pending.Margin=new Thickness(0,8,0,0);p.Children.Add(pending);
        var s=restart.Read();if(s!=null)p.Children.Add(Label(s.Message,11,true));p.Children.Add(Label(snapshot==null?"CTC reads chat records.":RestartGate.Reason(snapshot),11,true));
        var buttons=new WrapPanel();var now=Button("Restart now safely",()=>RequestRestart(),"Close and reopen Codex after all recorded chats are idle. Open windows will close.","RestartNow");now.IsEnabled=snapshot!=null&&RestartGate.Ready(snapshot)&&s?.Status is not("Waiting" or "Closing");now.Padding=new Thickness(7,4,7,4);now.Margin=new Thickness(0,0,5,5);buttons.Children.Add(now);
        var after=Button("Restart after all chats stop",RequestRestart,"Queue one normal restart. Unknown records block it. The request expires after 24 h.","RestartAfterIdle");after.IsEnabled=s?.Status is not("Waiting" or "Closing");after.Padding=new Thickness(7,4,7,4);after.Margin=new Thickness(0,0,0,5);buttons.Children.Add(after);
        var cancel=Button("Cancel restart",()=>{restart.Cancel();RenderQueue(true);});cancel.IsEnabled=s?.Status=="Waiting";cancel.Padding=new Thickness(7,4,7,4);cancel.Margin=new Thickness(0,0,0,5);buttons.Children.Add(cancel);p.Children.Add(buttons);p.Children.Add(Divider());
        var items=new StackPanel();
        foreach(var view in views)
        {
            var tile=new StackPanel();tile.Children.Add(Label(view.Entry.Path.Equals(Path.Combine(home,"config.toml"),StringComparison.OrdinalIgnoreCase)?"Global - all projects":Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(view.Entry.Path)))??view.Entry.Path,12));
            tile.Children.Add(Label("Saved window: "+Format.Tokens(view.Entry.Window)+" | Compact: "+Format.Tokens(view.Entry.Compact),10,true));
            tile.Children.Add(Label(view.Status,10));if(view.Error.Length>0)tile.Children.Add(Label(view.Error,10));tile.ToolTip=view.Entry.Path;items.Children.Add(new Border{Background=Controls.Panel,CornerRadius=new CornerRadius(6),Padding=new Thickness(8),Margin=new Thickness(0,0,0,8),Child=tile});
        }
        if(items.Children.Count==0)items.Children.Add(Label("No saved limit changes.",11));dock.Children.Add(Scroll(items));body.Content=dock;
    }
    private void RequestRestart()
    {
        restart.Request();var s=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
        foreach(string a in new[]{"--restart-helper","--home",home,"--data",data})s.ArgumentList.Add(a);Process.Start(s);RenderQueue(true);
    }
    private bool Open(string key,bool fallback=false)=>expanded.GetValueOrDefault(key,fallback);
    private void CaptureExpanded(DependencyObject? root)
    {
        if(root==null)return;
        if(root is Expander e&&AutomationProperties.GetAutomationId(e) is {Length:>0} id)expanded[id]=e.IsExpanded;
        for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++)CaptureExpanded(VisualTreeHelper.GetChild(root,i));
    }
    private static void OpenUrl(string url)=>Process.Start(new ProcessStartInfo(url){UseShellExecute=true});
}
