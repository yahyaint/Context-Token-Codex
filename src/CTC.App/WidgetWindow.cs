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

public sealed class WidgetWindow:Window
{
    private readonly string home,data,prefsPath;
    private readonly Host host;
    private readonly Preferences prefs;
    private readonly QueueStore queue;
    private readonly RestartController restart;
    private readonly Forms.NotifyIcon tray;
    private readonly Border frame;
    private readonly Grid shell;
    private readonly StackPanel quotas=new(){Orientation=Orientation.Horizontal};
    private readonly ContentControl body=new();
    private readonly TextBlock title=Label("",13),position=Label("",10,true),context=Label("",16),tokens=Label("",20);
    private readonly TextBlock status=Label("",10,true);
    private readonly ProgressBar contextBar=new(){Maximum=100,Height=5,Margin=new Thickness(0,5,0,6)};
    private readonly Button previous,next;
    private readonly StackPanel tabs=new(){Orientation=Orientation.Horizontal},appearance=new();
    private readonly WrapPanel toolbar=new();
    private readonly Dictionary<string,bool> expanded=new();
    private ChatView[] chats=[];
    private ChatView? selected;
    private string selectedId="",page="Context",signature="",quotaSignature="";
    private long shownRevision=-1;
    private bool parked,large,closing,dragging,applyingSize;
    private Point returnPoint;
    private string returnCorner;
    private ScrollViewer? contentScroll;
    private LimitEditor? editor;
    private MonitorSnapshot? snapshot;
    private readonly string[] args;

    public WidgetWindow(string home,string data,string[] args)
    {
        this.home=home;this.data=data;this.args=args;prefsPath=Path.Combine(data,"overlay.json");prefs=Preferences.Load(prefsPath);
        host=new(home,data,Array.IndexOf(args,"--ui-test")>=0);queue=new(Path.Combine(data,"limits-queue.json"),home);restart=new(Path.Combine(data,"restart.json"));
        parked=prefs.StartParked;large=!prefs.Compact;returnCorner=prefs.Corner;returnPoint=new(prefs.Left,prefs.Top);page=prefs.Mode;
        Title="Context-Token Codex";FontFamily=new FontFamily("Segoe UI");FontSize=12;
        WindowStyle=WindowStyle.None;AllowsTransparency=true;Background=Brushes.Transparent;ResizeMode=ResizeMode.NoResize;Topmost=prefs.Topmost;
        Icon=BitmapFrame.Create(new Uri("pack://application:,,,/ContextTokenCodex;component/Assets/Context.ico"));
        UseLayoutRounding=true;SnapsToDevicePixels=true;
        shell=new Grid();shell.RowDefinitions.Add(new(){Height=GridLength.Auto});shell.RowDefinitions.Add(new(){Height=GridLength.Auto});shell.RowDefinitions.Add(new(){Height=new GridLength(1,GridUnitType.Star)});shell.RowDefinitions.Add(new(){Height=GridLength.Auto});
        frame=new Border{CornerRadius=new CornerRadius(12),BorderBrush=Line,BorderThickness=new Thickness(1),Padding=new Thickness(12),Child=shell};Content=frame;SetOpacity(prefs.Opacity);
        var header=new DockPanel();
        var logo=Label("ctc",24);logo.FontWeight=FontWeights.SemiBold;logo.Margin=new Thickness(0,0,12,0);logo.ToolTip="Context-Token Codex";DockPanel.SetDock(logo,Dock.Left);header.Children.Add(logo);
        var actions=new StackPanel{Orientation=Orientation.Horizontal};DockPanel.SetDock(actions,Dock.Right);
        actions.Children.Add(Button("□",ToggleSize,"Expand or collapse the widget","Expand"));
        actions.Children.Add(Button("−",()=>SetParked(true),"Minimize to the parked bar","Minimize"));
        actions.Children.Add(Button("▾",HideToTray,"Hide to tray","Tray"));
        header.Children.Add(actions);
        var navigation=new StackPanel{Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center};
        previous=Button("‹",()=>Navigate(-1),"Previous chat","PreviousChat");next=Button("›",()=>Navigate(1),"Next chat","NextChat");
        previous.Padding=next.Padding=new Thickness(5,2,5,2);position.MinWidth=34;position.TextAlignment=TextAlignment.Center;
        navigation.Children.Add(previous);navigation.Children.Add(position);navigation.Children.Add(next);header.Children.Add(navigation);
        header.MouseLeftButtonDown+=(_,e)=>{if(e.OriginalSource is TextBlock||e.OriginalSource==header){dragging=true;try{DragMove();}finally{dragging=false;}prefs.Corner="Free";if(!large||parked){returnCorner="Free";returnPoint=new(Left,Top);}SavePreferences();}};
        shell.Children.Add(header);
        var summary=new StackPanel();Grid.SetRow(summary,1);shell.Children.Add(summary);
        title.TextTrimming=TextTrimming.CharacterEllipsis;title.TextWrapping=TextWrapping.NoWrap;summary.Children.Add(title);
        var main=new Grid();main.ColumnDefinitions.Add(new());main.ColumnDefinitions.Add(new());
        context.FontWeight=FontWeights.SemiBold;tokens.FontWeight=FontWeights.SemiBold;main.Children.Add(context);Grid.SetColumn(tokens,1);tokens.TextAlignment=TextAlignment.Right;main.Children.Add(tokens);summary.Children.Add(main);
        summary.Children.Add(contextBar);
        var quotaRow=new DockPanel();var refresh=Button("↻",()=>_=host.Refresh(),"Refresh account quotas","RefreshQuotas");refresh.Padding=new Thickness(5,2,5,2);DockPanel.SetDock(refresh,Dock.Right);quotaRow.Children.Add(refresh);quotaRow.Children.Add(quotas);summary.Children.Add(quotaRow);
        summary.Children.Add(tabs);tabs.Children.Add(Button("Context",()=>ShowPage("Context"),"Show context","ContextMode"));tabs.Children.Add(Button("Tokens",()=>ShowPage("Tokens"),"Show tokens","TokensMode"));
        tabs.Children.Add(Button("Limits",()=>ShowPage("Limits"),"Edit context limits","LimitsMode"));tabs.Children.Add(Button("Queue",()=>ShowPage("Queue"),"Show limits updates in queue","QueueMode"));
        Grid.SetRow(body,2);shell.Children.Add(body);
        var footer=new StackPanel();Grid.SetRow(footer,3);shell.Children.Add(footer);
        var backgroundRow=new DockPanel();var backgroundLabel=Label("Background",10,true);DockPanel.SetDock(backgroundLabel,Dock.Left);backgroundRow.Children.Add(backgroundLabel);
        var opacityLabel=Label("",10,true);opacityLabel.MinWidth=35;DockPanel.SetDock(opacityLabel,Dock.Right);backgroundRow.Children.Add(opacityLabel);
        var opacity=new Slider{Minimum=40,Maximum=100,Value=prefs.Opacity*100,Margin=new Thickness(8,0,8,0),ToolTip="Set background opacity. Text remains visible."};
        AutomationProperties.SetAutomationId(opacity,"BackgroundOpacity");
        opacity.ValueChanged+=(_,_)=>{prefs.Opacity=opacity.Value/100;SetOpacity(prefs.Opacity);opacityLabel.Text=$"{opacity.Value:0}%";SavePreferences();};backgroundRow.Children.Add(opacity);opacityLabel.Text=$"{opacity.Value:0}%";appearance.Children.Add(backgroundRow);footer.Children.Add(appearance);
        toolbar.Children.Add(Button("Corner",CycleCorner,"Move the widget to a screen corner","Corner"));
        var site=Button("yahyanabil.com",()=>OpenUrl("https://yahyanabil.com"),"Open yahyanabil.com");site.FontSize=10;site.BorderThickness=new Thickness(0);toolbar.Children.Add(site);
        toolbar.Children.Add(Button("Tray",HideToTray,"Hide to tray"));
        toolbar.Children.Add(Button("Edit context limits",()=>ShowPage("Limits"),"Edit context limits for this chat","EditContextLimits"));
        footer.Children.Add(toolbar);footer.Children.Add(status);
        tray=new Forms.NotifyIcon{Text="Context-Token Codex",Visible=true};
        using(var stream=Application.GetResourceStream(new Uri("/ContextTokenCodex;component/Assets/Context.ico",UriKind.Relative))!.Stream)tray.Icon=new System.Drawing.Icon(stream);
        var menu=new Forms.ContextMenuStrip();menu.Items.Add("Show",null,(_,_)=>Restore());menu.Items.Add("Minimize",null,(_,_)=>SetParked(true));menu.Items.Add("Exit",null,(_,_)=>Close());tray.ContextMenuStrip=menu;tray.DoubleClick+=(_,_)=>Restore();
        host.Changed+=()=>{if(!closing)Dispatcher.BeginInvoke(Update);};
        StateChanged+=(_,_)=>{if(WindowState==WindowState.Minimized){WindowState=WindowState.Normal;SetParked(true);}};
        SizeChanged+=(_,_)=>{if(IsLoaded&&large&&!parked&&!applyingSize){prefs.Width=Math.Max(460,ActualWidth);prefs.Height=Math.Max(520,ActualHeight);SavePreferences();}};
        Loaded+=async(_,_)=>{ApplySize();Place(returnCorner,returnPoint);if(Array.IndexOf(args,"--ui-test")>=0)_=UiChecks.Run(this,home,data,Program.Option(args,"--ui-test"));await Start();};
        Closing+=(_,_)=>{SavePreferences();closing=true;AtomicFile.Write(Path.Combine(data,"manual-close.txt"),DateTimeOffset.Now.ToString("o"));tray.Visible=false;tray.Dispose();host.Dispose();};
        ShowPage(page,false);ApplySize();
    }
    private async Task Start()
    {
        _=host.Start();
        string seconds=Program.Option(args,"--exit-after");
        if(double.TryParse(seconds,out double n)){await Task.Delay(TimeSpan.FromSeconds(n));Close();}
    }
    private void SetOpacity(double value){var brush=Ink;brush.Opacity=value;frame.Background=brush;}
    private void SavePreferences()
    {
        if(closing)return;
        prefs.Mode=page=="Tokens"?"Tokens":"Context";prefs.Compact=!large;prefs.Topmost=Topmost;
        // StartParked is the launch preference. Minimize does not change it.
        if((!large||parked)&&double.IsFinite(Left)&&double.IsFinite(Top)){prefs.Left=Left;prefs.Top=Top;}
        try{AtomicFile.Json(prefsPath,prefs);}catch(IOException e){status.Text=e.Message;}
    }
    public void Restore(){Show();ShowInTaskbar=true;WindowState=WindowState.Normal;Activate();}
    private void HideToTray(){Hide();ShowInTaskbar=false;tray.ShowBalloonTip(2500,"Context-Token Codex","CTC is in the Windows notification area.",Forms.ToolTipIcon.Info);}
    private void ToggleSize()
    {
        if(parked){SetParked(false);return;}
        if(!large){returnPoint=new(Left,Top);returnCorner=prefs.Corner;}
        large=!large;ApplySize();if(!large){prefs.Corner=returnCorner;Place(returnCorner,returnPoint);}else Place(prefs.Corner,new(Left,Top));
        SavePreferences();Render(true);
    }
    private void SetParked(bool value)
    {
        if(value&&!parked&&!large){returnPoint=new(Left,Top);returnCorner=prefs.Corner;}
        parked=value;ApplySize();Place(returnCorner,returnPoint);SavePreferences();Render(true);
    }
    private void ApplySize()
    {
        applyingSize=true;
        MinWidth=parked?0:390;MinHeight=large&&!parked?520:0;ResizeMode=large&&!parked?ResizeMode.CanResizeWithGrip:ResizeMode.NoResize;
        Width=parked?570:large?Math.Max(460,prefs.Width):390;Height=parked?178:large?prefs.Height:page=="Limits"?640:570;
        body.Visibility=parked?Visibility.Collapsed:Visibility.Visible;tabs.Visibility=parked?Visibility.Collapsed:Visibility.Visible;
        appearance.Visibility=parked?Visibility.Collapsed:Visibility.Visible;status.Visibility=parked?Visibility.Collapsed:Visibility.Visible;
        tokens.FontSize=parked?14:20;context.FontSize=parked?14:16;frame.Padding=new Thickness(parked?9:12);
        context.Visibility=tokens.Visibility=contextBar.Visibility=page=="Limits"&&!parked?Visibility.Collapsed:Visibility.Visible;
        foreach(UIElement element in toolbar.Children)element.Visibility=Visibility.Visible;
        toolbar.Children[1].Visibility=parked?Visibility.Collapsed:Visibility.Visible;
        toolbar.Children[2].Visibility=Visibility.Collapsed; // Tray is beside Expand in the header.
        toolbar.Children[3].Visibility=page is "Limits" or "Tokens"&&!parked?Visibility.Collapsed:Visibility.Visible;
        foreach(UIElement e in tabs.Children)
        {
            if(e is Button b&&b.Content is string s)b.Visibility=page=="Tokens"&&s is "Limits" or "Queue"?Visibility.Collapsed:Visibility.Visible;
        }
        applyingSize=false;
    }
    private void Place(string corner,Point free)
    {
        // Use the current monitor. WinForms coordinates are physical pixels; WPF uses device-independent units.
        var screen=Forms.Screen.FromPoint(new System.Drawing.Point((int)(Left*Dpi().X),(int)(Top*Dpi().Y)));
        var work=screen.WorkingArea;var dpi=Dpi();double l=work.Left/dpi.X,t=work.Top/dpi.Y,w=work.Width/dpi.X,h=work.Height/dpi.Y;
        Left=corner.Contains("Right")?l+w-Width-12:corner.Contains("Left")?l+12:Math.Clamp(free.X,l,l+Math.Max(0,w-Width));
        Top=corner.Contains("Bottom")?t+h-Height-12:corner.Contains("Top")?t+12:Math.Clamp(free.Y,t,t+Math.Max(0,h-Height));
    }
    private (double X,double Y) Dpi(){var d=VisualTreeHelper.GetDpi(this);return(d.DpiScaleX,d.DpiScaleY);}
    private void CycleCorner()
    {
        string[] values=["BottomRight","BottomLeft","TopLeft","TopRight"];int i=Array.IndexOf(values,prefs.Corner);prefs.Corner=values[(i+1)%values.Length];returnCorner=prefs.Corner;Place(returnCorner,returnPoint);returnPoint=new(Left,Top);SavePreferences();
    }
    private void Navigate(int delta)
    {if(chats.Length==0)return;int i=Array.FindIndex(chats,x=>x.Id==selectedId);selectedId=chats[(i+delta+chats.Length)%chats.Length].Id;shownRevision=-1;Update();}
    private void ShowPage(string name,bool unpark=true)
    {
        if(unpark&&parked){parked=false;large=false;ApplySize();Place(returnCorner,returnPoint);}
        if(name!=page)editor=null;page=name;ApplySize();if(IsLoaded&&!large)Place(returnCorner,returnPoint);Render(true);SavePreferences();
    }
    private void Update()
    {
        if(closing||dragging)return;snapshot=host.Snapshot;if(snapshot==null)return;
        var active=snapshot.ActiveChats;chats=(active.Length>0?active:snapshot.Chats.Where(x=>!x.Subagent).Take(100).ToArray());
        selected=chats.FirstOrDefault(x=>x.Id==selectedId)??chats.FirstOrDefault();selectedId=selected?.Id??"";
        title.Text=selected==null?"No recorded chats. Open Codex.":selected.Title+" | "+selected.Status;title.ToolTip=selected?.Initial;
        position.Text=chats.Length>0?$"{Array.IndexOf(chats,selected!)+1} / {chats.Length}":"0 / 0";previous.IsEnabled=next.IsEnabled=chats.Length>1;
        context.Text="Context "+Format.Percent(selected?.ContextPercent);tokens.Text=Format.Short(selected?.Total.Total)+" tokens";contextBar.Value=Math.Clamp(selected?.ContextPercent??0,0,100);
        context.ToolTip=selected==null?"No context record.":$"{Format.Tokens(selected.Latest.Input)} / {Format.Tokens(selected.Window)} tokens";
        tokens.ToolTip=Format.Tokens(selected?.Total.Total)+" recorded tokens";
        UpdateQuotas();
        status.Text=host.Error.Length>0?host.Error:snapshot.Warning.Length>0?snapshot.Warning:"Last record: "+(selected?.UsageAt.ToLocalTime().ToString("HH:mm:ss")??"--");
        Render(false);
    }
    private void UpdateQuotas()
    {
        var q=host.Quota;bool stale=q!=null&&DateTimeOffset.Now-q.Observed>TimeSpan.FromMinutes(2);string sig=q==null?"none":JsonSerializer.Serialize(q.Windows)+q.Observed+stale;
        if(sig==quotaSignature)return;quotaSignature=sig;quotas.Children.Clear();
        if(q==null){quotas.Children.Add(Label("Quota --",10,true));return;}
        foreach(var w in q.Windows.Take(3))
        {
            var p=new StackPanel{Width=parked?150:large?180:145,Margin=new Thickness(0,0,10,0)};
            p.Children.Add(Label(w.Label+" | "+Format.Percent(w.Used)+" used"+(stale?" *":""),10));p.Children.Add(new ProgressBar{Maximum=100,Value=w.Used,Height=4,Margin=new Thickness(0,2,0,4)});
            p.ToolTip=$"{q.Plan} | {w.Bucket}\n{Format.Percent(w.Remaining)} left\nReset: {w.Reset?.ToLocalTime().ToString("g")??"--"}\nObserved: {q.Observed.ToLocalTime():g}"+(stale?"\nThe reading is old. Select Refresh.":"");
            quotas.Children.Add(p);
        }
    }
    private void Render(bool force)
    {
        foreach(Button b in tabs.Children)b.Tag=(string)b.Content==page?"Selected":"";
        if(parked)return;
        if(page=="Limits")
        {
            if(editor==null){editor=new(home,queue,()=>selected,snapshot?.Projects??[],ShowQueue);body.Content=editor.View;}
            return;
        }
        if(page=="Queue"){RenderQueue(force);return;}
        if(!force&&selected?.Revision==shownRevision&&signature==selectedId+page)return;
        shownRevision=selected?.Revision??-1;signature=selectedId+page;
        double offset=contentScroll?.VerticalOffset??0;CaptureExpanded(body.Content as DependencyObject);
        var panel=new StackPanel();
        if(selected==null)panel.Children.Add(Label("No recorded chats are available."));
        else if(page=="Tokens")TokenPage(panel,selected);
        else ContextPage(panel,selected);
        contentScroll=Scroll(panel);body.Content=contentScroll;
        Dispatcher.BeginInvoke(()=>contentScroll.ScrollToVerticalOffset(offset),DispatcherPriority.Loaded);
    }
    private void ContextPage(StackPanel p,ChatView c)
    {
        var details=new StackPanel();details.Children.Add(Label(c.Model,12,true));details.Children.Add(Label($"{Format.Tokens(c.Latest.Input)} / {Format.Tokens(c.Window)} tokens",22));
        details.Children.Add(Label("Compactions: "+c.Compactions+" | Last: "+(c.LastCompact==default?"--":c.LastCompact.ToLocalTime().ToString("HH:mm:ss")),11,true));
        details.Children.Add(Button("Edit context limits",()=>ShowPage("Limits"),"Edit context limits for this chat"));p.Children.Add(Tile(details));
        var saved=new StackPanel();
        try
        {
            var paths=ContextSettings.ConfigPaths(home,c.Cwd);var limits=paths.Select(x=>(Path:x,Values:ContextSettings.ReadLimits(x))).FirstOrDefault(x=>x.Values.Window.HasValue||x.Values.Compact.HasValue);
            saved.Children.Add(Label("Saved window: "+Format.Limit(limits.Values?.Window)+" | Compact at: "+Format.Limit(limits.Values?.Compact)));
            saved.Children.Add(Label("Saved values need a fresh Codex session. Recorded values update after a model request.",11,true));
            if(limits.Path!=null)saved.ToolTip=limits.Path;
        }catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException){saved.Children.Add(Label(e.Message));}
        p.Children.Add(Details("Saved settings",saved,Open("saved"),"saved"));p.Children.Add(Divider());AddHelp(p,c);
    }
    private void TokenPage(StackPanel p,ChatView c)
    {
        p.Children.Add(Label("Quota estimate: "+host.Share(c.Id),11,true));
        var grid=new Grid();grid.ColumnDefinitions.Add(new());grid.ColumnDefinitions.Add(new());for(int i=0;i<4;i++)grid.RowDefinitions.Add(new(){Height=GridLength.Auto});
        string[] names=["Input","Cached input","Uncached input","Output","Reasoning","Other output"];long?[] values=[c.Total.Input,c.Total.Cached,c.Total.Uncached,c.Total.Output,c.Total.Reasoning,c.Total.OtherOutput];
        for(int i=0;i<6;i++){var tile=Metric(names[i],values[i]);Grid.SetRow(tile,i/2);Grid.SetColumn(tile,i%2);grid.Children.Add(tile);}
        var activity=new StackPanel();
        foreach(var tool in c.Activity.Tools)activity.Children.Add(ActivityTile(tool));
        var exec=new StackPanel();foreach(var detail in c.Activity.Exec)exec.Children.Add(ActivityTile(detail));
        var commands=new StackPanel();foreach(var x in c.Activity.CommandTypes)commands.Children.Add(Metric(x.Key,x.Value));
        var references=new StackPanel();foreach(var x in c.Activity.References)references.Children.Add(Metric(x.Key,x.Value));references.Children.Add(Label("Script references do not confirm execution.",10,true));
        var results=new StackPanel();foreach(var x in c.Activity.ShellResults)results.Children.Add(ActivityTile(x));
        exec.Children.Add(Details("Command types",commands,Open("commands"),"commands"));exec.Children.Add(Details("Script references",references,Open("references"),"references"));exec.Children.Add(Details("Shell results",results,Open("results"),"results"));
        activity.Children.Add(Details("Exec",exec,Open("exec"),"exec"));
        activity.Children.Add(Label("Call counts are recorded requests. CTC cannot assign exact token costs to each tool.",10,true));
        var toolHeader=new StackPanel();toolHeader.Children.Add(Label("Tool calls",10,true));toolHeader.Children.Add(Label(Format.Short(c.Activity.Calls)+(c.Activity.Partial?" *":""),22));
        var toolExpander=Details("",activity,Open("tools"),"tools");toolExpander.Header=toolHeader;
        var toolTile=Tile(toolExpander);Grid.SetRow(toolTile,3);Grid.SetColumnSpan(toolTile,2);grid.Children.Add(toolTile);
        p.Children.Add(Details("Breakdown",grid,Open("breakdown",true),"breakdown"));
        var latest=new StackPanel();latest.Children.Add(Label("Input: "+Format.Tokens(c.Latest.Input)+" | Cached: "+Format.Tokens(c.Latest.Cached)));latest.Children.Add(Label("Output: "+Format.Tokens(c.Latest.Output)+" | Reasoning: "+Format.Tokens(c.Latest.Reasoning)));
        p.Children.Add(Details("Latest request",latest,Open("latest"),"latest"));
        var recorded=new StackPanel();foreach(var x in (snapshot?.Chats??[]).Where(x=>!x.Subagent).Take(100)){var row=Button(x.Title+" · "+Format.Short(x.Total.Total),()=>{selectedId=x.Id;selected=x;shownRevision=-1;Render(true);},x.Title);recorded.Children.Add(row);}
        p.Children.Add(Details("Recorded chats",recorded,Open("recorded"),"recorded"));
        p.Children.Add(Divider());AddHelp(p,c);
    }
    private static Border Metric(string name,long? value)
    {var p=new StackPanel();p.Children.Add(Label(name,10,true));var n=Label(Format.Short(value),22);n.ToolTip=Format.Tokens(value);p.Children.Add(n);return Tile(p);}
    private static Border ActivityTile(ActivityDetail d)
    {var p=new StackPanel();p.Children.Add(Label(d.Name,10,true));p.Children.Add(Label(Format.Short(d.Count),20));p.Children.Add(Label($"Results {d.WithResult:N0} | No result {d.NoResult:N0}",10,true));p.Children.Add(Label($"Success {d.Success:N0} | Failure {d.Failure:N0} | Unknown {d.Unknown:N0}",10,true));p.Children.Add(Label($"Recorded time {d.Seconds:0.#} s",10,true));return Tile(p);}
    private void AddHelp(StackPanel p,ChatView c)
    {
        var row=new Grid();row.ColumnDefinitions.Add(new());row.ColumnDefinitions.Add(new());
        var dataText=new StackPanel();dataText.Children.Add(Label("Last record: "+(c.UsageAt==default?"--":c.UsageAt.ToLocalTime().ToString("g")),10,true));dataText.Children.Add(Label(snapshot?.CompactionSource??"Rollout records",10,true));dataText.Children.Add(Label(c.Error.Length>0?c.Error:"Counts include earlier requests and models in this chat.",10,true));
        var countText=new StackPanel();countText.Children.Add(Label("Input includes cached input. Output includes reasoning. Total is input plus output.",10,true));countText.Children.Add(Label("Quota estimates use observed changes and model weights. Other devices can affect these estimates.",10,true));
        var left=Details("Data status",dataText,Open("data"),"data");left.FontSize=10;var right=Details("How counts work",countText,Open("counts"),"counts");right.FontSize=10;Grid.SetColumn(right,1);row.Children.Add(left);row.Children.Add(right);p.Children.Add(row);
        if(large){p.Children.Add(Label("Yahya Nabil",10,true));p.Children.Add(Button("App settings",ShowAppearance,"Set startup and window options"));}
    }
    private void ShowAppearance()
    {
        var p=new StackPanel();
        var auto=new CheckBox{Content="Auto-open with app",IsChecked=prefs.AutoOpen,Margin=new Thickness(0,8,0,8)};
        auto.Checked+=(_,_)=>SetAuto(true);auto.Unchecked+=(_,_)=>SetAuto(false);p.Children.Add(auto);
        var top=new CheckBox{Content="On top",IsChecked=Topmost,Margin=new Thickness(0,4,0,8)};top.Checked+=(_,_)=>{Topmost=true;SavePreferences();};top.Unchecked+=(_,_)=>{Topmost=false;SavePreferences();};p.Children.Add(top);
        var park=new CheckBox{Content="Open in the small bar",IsChecked=prefs.StartParked,Margin=new Thickness(0,4,0,8)};park.Checked+=(_,_)=>{prefs.StartParked=true;SavePreferences();};park.Unchecked+=(_,_)=>{prefs.StartParked=false;SavePreferences();};p.Children.Add(park);
        var target=new ComboBox{ItemsSource=new[]{"Either","Codex","ChatGPT"},SelectedItem=prefs.Target,Margin=new Thickness(0,4,0,8)};target.SelectionChanged+=(_,_)=>{prefs.Target=(string)target.SelectedItem;SavePreferences();};p.Children.Add(Label("Open with"));p.Children.Add(target);
        p.Children.Add(Label("The startup watcher uses app paths. It supports Codex package updates.",11,true));p.Children.Add(Button("Back",()=>Render(true)));body.Content=p;
    }
    private void SetAuto(bool enabled){prefs.AutoOpen=enabled;SavePreferences();try{Installer.SetStartup(AppContext.BaseDirectory,data,enabled);if(enabled)Installer.StartWatcher(AppContext.BaseDirectory,data);}catch(Exception e) when(e is IOException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException){status.Text=e.Message;}}
    private void ShowQueue()=>ShowPage("Queue");
    private void RenderQueue(bool force)
    {
        string sig="";
        QueueView[] views;
        try{views=queue.Views(snapshot?.Chats??[]);sig=JsonSerializer.Serialize(views)+JsonSerializer.Serialize(restart.Read())+(snapshot==null?"":RestartGate.Reason(snapshot));}
        catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException){body.Content=Label(e.Message);return;}
        if(!force&&signature==sig)return;signature=sig;
        var p=new StackPanel();p.Children.Add(Label(views.Length>0?"Limits updates in queue":"No saved limit changes.",18));
        var s=restart.Read();if(s!=null)p.Children.Add(Label(s.Message,11,true));p.Children.Add(Label(snapshot==null?"CTC reads chat records.":RestartGate.Reason(snapshot),11,true));
        var buttons=new WrapPanel();var now=Button("Restart now safely",()=>RequestRestart(),"Close and reopen Codex after all recorded chats are idle. Open windows will close.","RestartNow");now.IsEnabled=snapshot!=null&&RestartGate.Ready(snapshot)&&s?.Status is not("Waiting" or "Closing");buttons.Children.Add(now);
        var after=Button("Restart after all chats stop",RequestRestart,"Queue one normal restart. Unknown records block it. The request expires after 24 h.","RestartAfterIdle");after.IsEnabled=s?.Status is not("Waiting" or "Closing");buttons.Children.Add(after);
        var cancel=Button("Cancel restart",()=>{restart.Cancel();RenderQueue(true);});cancel.IsEnabled=s?.Status=="Waiting";buttons.Children.Add(cancel);p.Children.Add(buttons);p.Children.Add(Divider());
        foreach(var view in views)
        {
            var tile=new StackPanel();tile.Children.Add(Label(view.Entry.Path.Equals(Path.Combine(home,"config.toml"),StringComparison.OrdinalIgnoreCase)?"Global - all projects":Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(view.Entry.Path)))??view.Entry.Path,14));
            tile.Children.Add(Label("Window: "+Format.Limit(view.Entry.Window)+" | Compact at: "+Format.Limit(view.Entry.Compact),11,true));
            tile.Children.Add(Label(view.Status,11));if(view.Error.Length>0)tile.Children.Add(Label(view.Error,11));tile.ToolTip=view.Entry.Path;p.Children.Add(Tile(tile));
        }
        body.Content=Scroll(p);
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
