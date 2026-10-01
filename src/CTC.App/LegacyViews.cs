// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using CTC.Core;
using static CTC.App.Controls;

namespace CTC.App;
public sealed partial class WidgetWindow
{
    private readonly Dictionary<string,LimitEditor> inlineEditors=new();
    private bool? previousActiveTokenState;
    private static Expander LegacyDetails(string name,UIElement content,bool open=false,string id="")
    {var e=Controls.Details(name,content,open,id);e.Margin=new Thickness(0);return e;}
    private static Border LegacyTile(UIElement body)=>new(){Background=Controls.Panel,CornerRadius=new CornerRadius(6),Padding=new Thickness(8),Margin=new Thickness(0,0,5,5),Child=body};
    private static Border LegacyMetric(string name,long? value)
    {var p=new StackPanel();p.Children.Add(Label(name,10,true));var n=Label(Format.Short(value),18);n.ToolTip=Format.Tokens(value)+" tokens";p.Children.Add(n);return LegacyTile(p);}
    private static UniformGrid ActivityGrid(IEnumerable<(string Name,string Value)> values)
    {
        var grid=new UniformGrid{Columns=3};
        foreach(var pair in values){var cell=new StackPanel{Margin=new Thickness(0,5,5,5)};cell.Children.Add(Label(pair.Name,9,true));cell.Children.Add(Label(pair.Value,16));grid.Children.Add(cell);}
        return grid;
    }
    private void RenderContextCards()
    {
        var panel=Main<StackPanel>("Cards");panel.Children.Clear();
        foreach(var c in snapshot?.ActiveChats??[])
        {
            var tile=new Border{Background=Controls.Panel,CornerRadius=new CornerRadius(10),Padding=new Thickness(14),Margin=new Thickness(0,0,0,10)};
            var p=new StackPanel();tile.Child=p;
            p.Children.Add(Label(c.Status.ToUpperInvariant(),12,true));var name=Label(c.Title,17);name.FontWeight=FontWeights.SemiBold;name.ToolTip="Initial: "+c.Initial+"\nChat: "+c.Id;p.Children.Add(name);
            var model=Label(c.Model);model.ToolTip=c.Cwd;p.Children.Add(model);
            p.Children.Add(Label(c.ContextPercent is {} percent?$"{percent:N1}%   {Format.Tokens(c.Latest.Input)} / {Format.Tokens(c.Window)} tokens":"No token usage record"));
            p.Children.Add(new ProgressBar{Height=7,Maximum=100,Value=Math.Clamp(c.ContextPercent??0,0,100),Margin=new Thickness(0,7,0,7)});
            var detail=new StackPanel();
            try{var baseline=new ModelCatalog(home).Baseline(Path.Combine(c.Cwd,".codex","config.toml"),c);detail.Children.Add(Label("Saved window: "+Format.Limit(baseline.Saved.Window)+" | Compact: "+Format.Limit(baseline.Saved.Compact),11,true));}
            catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException){detail.Children.Add(Label(e.Message,11));}
            detail.Children.Add(Label($"Compactions: {c.Compactions}  |  Last event: {c.LastEvent.ToLocalTime():HH:mm:ss}\nCached input: {Format.Tokens(c.Latest.Cached)}  |  Output: {Format.Tokens(c.Latest.Output)}",11));
            p.Children.Add(LegacyDetails("Details",detail,Open(c.Id+"details"),c.Id+"details"));
            if(c.Cwd.Length>0)
            {
                if(!inlineEditors.TryGetValue(c.Id,out var inline)){inline=new(home,queue,()=>snapshot?.Chats.FirstOrDefault(x=>x.Id==c.Id)??c,[c.Cwd],()=>ShowPage("Context"),true);inlineEditors[c.Id]=inline;}
                if(inline.View.Parent is ContentControl old)old.Content=null;
                if(inline.View.Parent is Expander oldEditor)oldEditor.Content=null;
                var edit=LegacyDetails("Edit context limits",inline.View,Open(c.Id+"edit"),c.Id+"edit");edit.Margin=new Thickness(0,8,0,0);p.Children.Add(edit);
            }
            panel.Children.Add(tile);
        }
        if(panel.Children.Count==0)panel.Children.Add(Label("No active chats.",17));
    }
    private void RenderTokens()
    {
        var viewer=Main<ScrollViewer>("TokensPanel");double offset=viewer.VerticalOffset;
        var rows=(snapshot?.Chats??[]).Where(c=>!c.Subagent).ToArray();var active=rows.Where(c=>c.Active).ToArray();
        var activePanel=Main<StackPanel>("ActiveTokenTasks");var otherPanel=Main<StackPanel>("TokenTasks");activePanel.Children.Clear();otherPanel.Children.Clear();
        Main<TextBlock>("ActiveTokenHeading").Visibility=active.Length>0?Visibility.Visible:Visibility.Collapsed;
        bool hasActive=active.Length>0;if(previousActiveTokenState!=hasActive){expanded["recorded"]=!hasActive;previousActiveTokenState=hasActive;}
        var recorded=Main<Expander>("TokenSummary");AutomationProperties.SetAutomationId(recorded,"recorded");recorded.IsExpanded=Open("recorded",!hasActive);
        foreach(var c in rows)
        {
            string key=c.Id==selected?.Id?"":c.Id+":";
            var row=new StackPanel{Margin=new Thickness(0,3,0,9)};
            row.Children.Add(Label(c.Title+" | "+(c.Active?"Running":"Idle"),13,true));
            var total=Label(Format.Tokens(c.Total.Total)+" tokens",25);total.ToolTip="These counts include previous requests in this chat.";row.Children.Add(total);
            row.Children.Add(Label("Quota estimate: "+host.Share(c.Id),11,true));
            bool open=Open(key+"breakdown");var breakdown=LegacyDetails("Breakdown",open?TokenDetails(c,key):new StackPanel(),open,key+"breakdown");
            // Keep the original view. Build hidden detail controls only when the user opens them.
            bool built=open;breakdown.Expanded+=(_,_)=>{if(!built){breakdown.Content=TokenDetails(c,key);built=true;}};
            breakdown.Margin=new Thickness(0,5,0,0);row.Children.Add(breakdown);
            (c.Active?activePanel:otherPanel).Children.Add(row);
        }
        long? Sum(Func<ChatView,long?> value)
        {var values=rows.Select(value).Where(n=>n.HasValue).Select(n=>n!.Value).ToArray();if(values.Length==0)return null;long n=0;foreach(long v in values){var sum=Usage.Sum(n,v);if(sum==null)return null;n=sum.Value;}return n;}
        Main<TextBlock>("TokenTotal").Text=Format.Tokens(Sum(c=>c.Total.Total));
        Main<TextBlock>("TokenLive").Text=host.Error.Length>0?"Read error":"File check | 1 s";
        Main<TextBlock>("TokenBreakdown").Text=rows.Length+" chats | Last record "+(rows.Length>0?rows.Max(c=>c.UsageAt).ToLocalTime().ToString("HH:mm:ss"):"--");
        var totals=Main<UniformGrid>("TokenMetrics");totals.Children.Clear();
        foreach(var pair in new[]{("Input",Sum(c=>c.Total.Input)),("Output",Sum(c=>c.Total.Output)),("Cache",Sum(c=>c.Total.Cached)),("Uncached",Sum(c=>c.Total.Uncached)),("Reasoning",Sum(c=>c.Total.Reasoning))})
        {var cell=new StackPanel{Margin=new Thickness(0,0,8,4)};cell.Children.Add(Label(pair.Item1,10,true));cell.Children.Add(Label(Format.Tokens(pair.Item2),17));totals.Children.Add(cell);}
        var cache=Sum(c=>c.Total.Cached);var input=Sum(c=>c.Total.Input);var hit=new StackPanel{Margin=new Thickness(0,0,8,4)};hit.Children.Add(Label("Cache hit",10,true));hit.Children.Add(Label(input>0&&cache!=null?$"{100d*cache/input:N1}%":"--",17));totals.Children.Add(hit);
        Main<TextBlock>("TokenSource").Text=host.Quota is {} q?$"{q.Source} | {q.Plan} | checked {q.Observed.ToLocalTime():MMM d HH:mm:ss}":"No quota reading is available. Sign in to Codex.";
        Main<TextBlock>("TokenCoverage").Text="Total = input + output.\nInput includes cached input. Output includes reasoning.\n-- means no value. * means incomplete data.\nQuotas apply to the account. Token counts come from this device.";
        Dispatcher.BeginInvoke(()=>viewer.ScrollToVerticalOffset(offset),System.Windows.Threading.DispatcherPriority.Loaded);
    }
    private StackPanel TokenDetails(ChatView c,string key)
    {
        var panel=new StackPanel();var grid=new Grid();grid.ColumnDefinitions.Add(new());grid.ColumnDefinitions.Add(new());for(int i=0;i<4;i++)grid.RowDefinitions.Add(new(){Height=GridLength.Auto});
        string[] names=["Input","Output","Cached input","Uncached input","Reasoning","Other output"];
        long?[] values=[c.Total.Input,c.Total.Output,c.Total.Cached,c.Total.Uncached,c.Total.Reasoning,c.Total.OtherOutput];
        for(int i=0;i<6;i++){var tile=LegacyMetric(names[i],values[i]);Grid.SetRow(tile,i/2);Grid.SetColumn(tile,i%2);grid.Children.Add(tile);}
        var activity=new StackPanel();
        var otherTools=c.Activity.Tools.Where(x=>!c.Activity.Exec.Any(e=>e.Name==x.Name)).ToArray();
        activity.Children.Add(Label(string.Join("\n",otherTools.Take(6).Select(x=>x.Name+"   "+Format.Tokens(x.Count))),11));
        var exec=new StackPanel();var details=c.Activity.Exec;long count=details.Sum(x=>x.Count);
        exec.Children.Add(ActivityGrid(new[]{("Results",Format.Short(details.Sum(x=>x.WithResult))),("Succeeded",Format.Short(details.Sum(x=>x.Success))),("Errors",Format.Short(details.Sum(x=>x.Failure))),("No result",Format.Short(details.Sum(x=>x.NoResult))),("Status unknown",Format.Short(details.Sum(x=>x.Unknown))),("Recorded time",details.Sum(x=>x.Seconds).ToString("0.#")+" s")}));
        exec.Children.Add(Label(count>0?string.Join("\n",details.Select(x=>x.Name+"   "+Format.Tokens(x.Count))):"No exec call record.",10));
        var commands=new StackPanel();commands.Children.Add(Label("Recorded requests",10,true));commands.Children.Add(ActivityGrid(c.Activity.CommandTypes.OrderBy(x=>x.Key).Select(x=>(x.Key,Format.Short(x.Value)))));
        exec.Children.Add(LegacyDetails("Command types",commands,Open(key+"commands"),key+"commands"));
        var refs=Label(c.Activity.References.Length>0?string.Join("\n",c.Activity.References.Select(x=>x.Key+"   "+Format.Tokens(x.Value))):"No direct script tool references.",10);
        refs.ToolTip="Direct script references do not confirm execution.";
        exec.Children.Add(LegacyDetails("Script tools: "+Format.Short(c.Activity.References.Sum(x=>x.Value))+" references",refs,Open(key+"references"),key+"references"));
        var shell=new StackPanel();var results=c.Activity.ShellResults;
        shell.Children.Add(ActivityGrid(new[]{("Results",Format.Short(results.Sum(x=>x.Count))),("Succeeded",Format.Short(results.Sum(x=>x.Success))),("Nonzero exit",Format.Short(results.Sum(x=>x.Failure))),("Open-process records",Format.Short(results.Where(x=>x.Name=="Running").Sum(x=>x.Count))),("Reported time",results.Sum(x=>x.Seconds).ToString("0.#")+" s")}));
        shell.Children.Add(Label(results.Length>0?"Exit codes":"No shell result metadata.",10,true));shell.Children.Add(ActivityGrid(results.Where(x=>x.Name!="Running").Select(x=>("Exit "+x.Name,Format.Short(x.Count)))));
        exec.Children.Add(LegacyDetails("Shell results: "+Format.Short(results.Sum(x=>x.Count)),shell,Open(key+"results"),key+"results"));
        var execView=LegacyDetails("Exec: "+Format.Tokens(count),exec,Open(key+"exec"),key+"exec");execView.Margin=new Thickness(0,4,0,0);activity.Children.Add(execView);
        var toolHeader=new StackPanel();toolHeader.Children.Add(Label("Tool calls",10,true));toolHeader.Children.Add(Label(Format.Short(c.Activity.Calls)+(c.Activity.Partial?" *":""),18));
        var tools=LegacyDetails("",activity,Open(key+"tools"),key+"tools");tools.Header=toolHeader;tools.Margin=new Thickness(0);tools.Template=LegacyLayouts.Load<ControlTemplate>("ToolCalls");
        var toolTile=LegacyTile(tools);Grid.SetRow(toolTile,3);Grid.SetColumnSpan(toolTile,2);grid.Children.Add(toolTile);panel.Children.Add(grid);
        panel.Children.Add(new Border{Height=1,Background=Line,Margin=new Thickness(0,7,0,7)});
        panel.Children.Add(Label($"Cache hit: {Format.Percent(c.Total.CacheRate)}   |   Reasoning share: {Format.Percent(c.Total.ReasoningRate)}",10,true));
        panel.Children.Add(LegacyDetails("Latest request",Label($"Input: {Format.Tokens(c.Latest.Input)}\nCached input: {Format.Tokens(c.Latest.Cached)}\nOutput: {Format.Tokens(c.Latest.Output)}",10),Open(key+"latest"),key+"latest"));
        panel.Children.Add(LegacyDetails("Data and estimate",Label($"Last model: {c.Model}\nLast record: {c.UsageAt.ToLocalTime():MMM d HH:mm:ss}\nTotals include earlier models. Cache is part of input. Reasoning is part of output.\nQuota shares are estimates. Tool counts do not measure token cost.",10),Open(key+"estimate"),key+"estimate"));
        return panel;
    }
    private void RenderAppearance()
    {
        var view=LegacyLayouts.Load<UserControl>("Settings");T Find<T>(string name) where T:class=>(T)view.FindName(name);
        Find<StackPanel>("ContextSettings").Visibility=Visibility.Collapsed;Find<StackPanel>("LimitActions").Visibility=Visibility.Collapsed;
        var opacity=Find<Slider>("OpacitySlider");opacity.Value=prefs.Opacity*100;
        Find<TextBlock>("OpacityLabel").Text=$"Background opacity: {opacity.Value:N0}%";
        opacity.ValueChanged+=(_,_)=>{Main<Slider>("LiveOpacity").Value=opacity.Value;Find<TextBlock>("OpacityLabel").Text=$"Background opacity: {opacity.Value:N0}%";};
        var corner=Find<ComboBox>("Corner");string[] corners=["Free","TopLeft","TopRight","BottomLeft","BottomRight"];corner.SelectedIndex=Array.IndexOf(corners,prefs.Corner);
        corner.SelectionChanged+=(_,_)=>{if(corner.SelectedIndex<0)return;prefs.Corner=corners[corner.SelectedIndex];returnCorner=prefs.Corner;Place(returnCorner,returnPoint);SavePreferences();};
        var park=Find<CheckBox>("StartParked");park.IsChecked=prefs.StartParked;park.Checked+=(_,_)=>{prefs.StartParked=true;SavePreferences();};park.Unchecked+=(_,_)=>{prefs.StartParked=false;SavePreferences();};
        var auto=Find<CheckBox>("Auto");auto.IsChecked=prefs.AutoOpen;auto.Checked+=(_,_)=>SetAuto(true);auto.Unchecked+=(_,_)=>SetAuto(false);
        var target=Find<ComboBox>("Target");string[] targets=["Codex","ChatGPT","Either"];target.SelectedIndex=Array.IndexOf(targets,prefs.Target);target.SelectionChanged+=(_,_)=>{prefs.Target=targets[target.SelectedIndex];SavePreferences();};
        Find<Button>("SaveApp").Click+=(_,_)=>{SavePreferences();ShowPage("Context");};Find<Button>("WidgetBack").Click+=(_,_)=>ShowPage("Context");body.Content=view;
    }
}
