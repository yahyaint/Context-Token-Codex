// SPDX-License-Identifier: MIT
using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using CTC.Core;
using static CTC.App.Controls;

namespace CTC.App;
public sealed class LimitEditor
{
    public DockPanel View {get;}=new();
    private readonly string home;
    private readonly QueueStore queue;
    private readonly Func<ChatView?> chat;
    private readonly TextBox window=new(){Padding=new Thickness(8),Margin=new Thickness(0,3,0,5)},compact=new(){Padding=new Thickness(8),Margin=new Thickness(0,3,0,5)};
    private readonly TextBlock current=Label("",10,true),hint=Label("",10,true),result=Label("",11),baseLabel=Label("",10,true);
    private readonly TextBlock capacity=Label("",11,true);
    private readonly ComboBox scope=new(){Margin=new Thickness(0,5,0,8)};
    private readonly Button save;
    private LimitBaseline? baseline;
    private string path="";
    public LimitEditor(string home,QueueStore queue,Func<ChatView?> chat,string[] projects,Action showQueue)
    {
        this.home=home;this.queue=queue;this.chat=chat;
        var body=new StackPanel();body.Children.Add(Label("Context limits",20));
        var paths=new[]{Path.Combine(home,"config.toml")}.Concat(projects.Where(Path.IsPathFullyQualified).Select(p=>Path.Combine(p,".codex","config.toml")));
        if(chat()?.Cwd is {Length:>0} cwd)paths=paths.Append(Path.Combine(cwd,".codex","config.toml"));
        var choices=paths.Distinct(StringComparer.OrdinalIgnoreCase).Select(p=>new ScopeChoice(p,p.Equals(Path.Combine(home,"config.toml"),StringComparison.OrdinalIgnoreCase)?"Global - all projects":Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(p)))??p)).ToArray();
        scope.ItemsSource=choices;scope.DisplayMemberPath="Label";body.Children.Add(scope);
        scope.SelectionChanged+=(_,_)=>{path=((ScopeChoice)scope.SelectedItem).Path;Load();};body.Children.Add(current);
        body.Children.Add(Label("Context window",12));body.Children.Add(window);AutomationProperties.SetAutomationId(window,"WindowInput");
        var scalers=new WrapPanel();
        foreach(int n in new[]{1,2,3})scalers.Children.Add(Button("x"+n,()=>Scale(n),"Set "+n+" times the base window. Model capacity does not increase.","Scale"+n));body.Children.Add(scalers);body.Children.Add(baseLabel);
        body.Children.Add(Label("Compact at",12));body.Children.Add(compact);AutomationProperties.SetAutomationId(compact,"CompactInput");
        var percentages=new WrapPanel();foreach(int n in new[]{80,90,95})percentages.Children.Add(Button(n+"%",()=>compact.Text=n+"%","Set compaction at "+n+"% of the entered window.","Percent"+n));body.Children.Add(percentages);
        var reset=new WrapPanel();reset.Children.Add(Button("Undo",Load,"Load the saved values again.","UndoLimits"));reset.Children.Add(Button("Default",()=>{window.Text="default";compact.Text="default";},"Remove both overrides after Save.","DefaultLimits"));body.Children.Add(reset);
        body.Children.Add(hint);body.Children.Add(Details("Input examples",Label("Window: 200000 or 200k. Compact at: 180000, 180k, or 90%. Use default to remove an override.",11,true)));
        var capacityBody=new StackPanel();capacityBody.Children.Add(capacity);capacityBody.Children.Add(Label("These settings apply to all models in this scope. A larger number cannot increase model capacity. Running chats need a fresh Codex session.",11,true));
        body.Children.Add(Details("Model capacity",capacityBody));
        body.Children.Add(result);
        var footer=new StackPanel{Margin=new Thickness(0,8,0,0)};DockPanel.SetDock(footer,Dock.Bottom);View.Children.Add(footer);
        save=Button("Save context limits",Save,"Save both limits and add a queue entry.","SaveLimits");save.HorizontalAlignment=HorizontalAlignment.Stretch;footer.Children.Add(save);footer.Children.Add(Button("Open queue",showQueue,"Show saved changes and restart controls."));
        View.Children.Add(Scroll(body));
        window.TextChanged+=(_,_)=>Hint();compact.TextChanged+=(_,_)=>Hint();
        string preferred=chat()?.Cwd is {Length:>0} project?Path.Combine(project,".codex","config.toml"):Path.Combine(home,"config.toml");
        scope.SelectedItem=choices.FirstOrDefault(x=>x.Path.Equals(preferred,StringComparison.OrdinalIgnoreCase))??choices[0];
    }
    private sealed record ScopeChoice(string Path,string Label);
    private void Load()
    {
        try
        {
            var selected=chat();bool related=selected!=null&&ContextSettings.ConfigPaths(home,selected.Cwd).Contains(path,StringComparer.OrdinalIgnoreCase);
            baseline=new ModelCatalog(home).Baseline(path,related?selected:null);window.Text=Format.Limit(baseline.Saved.Window);compact.Text=Format.Limit(baseline.Saved.Compact);
            current.Text="Saved: "+Format.Limit(baseline.Saved.Window)+" / "+Format.Limit(baseline.Saved.Compact)+" | Recorded window: "+Format.Short(baseline.Live);
            baseLabel.Text="Base: "+Format.Short(baseline.Base)+" · "+baseline.Source;baseLabel.ToolTip=path;result.Text="";save.IsEnabled=true;
            capacity.Text=baseline.Catalog?.Maximum is { } maximum?baseline.Model+" | Local capacity: "+Format.Tokens(maximum)+" tokens.":"Local model capacity is unknown.";
        }
        catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException){baseline=null;result.Text=e.Message;save.IsEnabled=false;}
        Hint();
    }
    private void Hint()
    {
        try{var v=ContextSettings.Draft(window.Text,compact.Text);hint.Text=v.Window.HasValue&&v.Compact.HasValue?$"Compact at: {Format.Tokens(v.Compact)} tokens = {100d*v.Compact/v.Window:0.#}% of the window.":"Example: 180k = 90% of 200k.";
            if(baseline?.Catalog?.Maximum is { } maximum&&v.Window>maximum)hint.Text+=" This value exceeds local model capacity.";
            if(baseline!=null)save.IsEnabled=true;}
        catch(ArgumentException e){hint.Text=e.Message;if(save!=null)save.IsEnabled=false;}
    }
    private void Scale(int n)
    {
        try{if(baseline?.Base==null&&baseline!=null)baseline=baseline with{Base=ContextSettings.Parse(window.Text),Source="entered window"};var v=ContextSettings.Scale(baseline?.Base,n,window.Text,compact.Text);window.Text=v.Window;compact.Text=v.Compact;result.Text="";baseLabel.Text="Base: "+Format.Short(baseline?.Base)+" · "+baseline?.Source;}
        catch(ArgumentException e){result.Text=e.Message;}
    }
    private void Save()
    {
        bool written=false;
        try
        {
            if(baseline==null)return;
            var values=ContextSettings.Draft(window.Text,compact.Text);
            _=queue.Read(); // Validate queue before changing settings.
            bool changed=ContextSettings.Save(path,values,baseline.Version);
            written=changed;
            if(changed)queue.Save(path,values);
            Load();result.Text=changed?"Saved. Limits updates in queue. Open Queue to reload Codex.":"The values already match the saved settings.";
        }
        catch(Exception e) when(e is IOException or InvalidDataException or System.Text.Json.JsonException or UnauthorizedAccessException or ArgumentException){result.Text=(written?"Settings were saved. The queue could not be written. ":"")+e.Message;}
    }
}
