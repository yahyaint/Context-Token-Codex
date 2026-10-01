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
    public System.Windows.Controls.UserControl View {get;}
    private readonly string home;
    private readonly QueueStore queue;
    private readonly Func<ChatView?> chat;
    private readonly TextBox window,compact;
    private readonly TextBlock current,hint,result,baseLabel;
    private readonly ComboBox scope;
    private readonly Button save;
    private LimitBaseline? baseline;
    private string path="";
    public LimitEditor(string home,QueueStore queue,Func<ChatView?> chat,string[] projects,Action showQueue,bool inline=false)
    {
        this.home=home;this.queue=queue;this.chat=chat;
        View=LegacyLayouts.Load<System.Windows.Controls.UserControl>("Settings");
        T Find<T>(string name) where T:class=>(T)View.FindName(name);
        Find<StackPanel>("AppearanceSettings").Visibility=Visibility.Collapsed;
        scope=Find<ComboBox>("Scope");window=Find<TextBox>("Context");compact=Find<TextBox>("Compact");
        current=Find<TextBlock>("Current");hint=Find<TextBlock>("CompactHint");result=Find<TextBlock>("LimitResult");baseLabel=Label("",10);
        save=Find<Button>("SaveLimits");save.Click+=(_,_)=>Save();AutomationProperties.SetAutomationId(save,"SaveLimits");
        Find<Button>("BackTasks").Click+=(_,_)=>showQueue();
        var paths=new[]{Path.Combine(home,"config.toml")}.Concat(projects.Where(Path.IsPathFullyQualified).Select(p=>Path.Combine(p,".codex","config.toml")));
        if(chat()?.Cwd is {Length:>0} cwd)paths=paths.Append(Path.Combine(cwd,".codex","config.toml"));
        var choices=paths.Distinct(StringComparer.OrdinalIgnoreCase).Select(p=>new ScopeChoice(p,p.Equals(Path.Combine(home,"config.toml"),StringComparison.OrdinalIgnoreCase)?"Global - all projects":"Project - "+(Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(p)))??p))).ToArray();
        scope.ItemsSource=choices;scope.DisplayMemberPath="Label";scope.SelectionChanged+=(_,_)=>{path=((ScopeChoice)scope.SelectedItem).Path;Load();};
        AutomationProperties.SetAutomationId(window,"WindowInput");AutomationProperties.SetAutomationId(compact,"CompactInput");
        var scalers=new WrapPanel();
        foreach(int n in new[]{1,2,3}){var b=Button("×"+n,()=>Scale(n),"Set "+n+" times the base window. Model capacity does not increase.","Scale"+n);b.Padding=new Thickness(8,3,8,3);scalers.Children.Add(b);}
        Find<StackPanel>("ContextQuick").Children.Add(scalers);Find<StackPanel>("ContextQuick").Children.Add(baseLabel);
        foreach(int n in new[]{80,90,95}){var b=Button(n+"%",()=>compact.Text=n+"%","Set compaction at "+n+"% of the entered window.","Percent"+n);b.Padding=new Thickness(7,3,7,3);b.Margin=new Thickness(0,0,6,4);Find<WrapPanel>("CompactQuick").Children.Add(b);}
        var undo=Button("Undo",Load,"Load the saved values again.","UndoLimits");undo.Padding=new Thickness(8,3,8,3);
        var reset=Button("Default",()=>{window.Text="default";compact.Text="default";},"Remove both overrides after Save.","DefaultLimits");reset.Padding=new Thickness(8,3,8,3);
        Find<WrapPanel>("ResetQuick").Children.Add(undo);Find<WrapPanel>("ResetQuick").Children.Add(reset);
        if(inline)
        {
            scope.Visibility=Visibility.Collapsed;Find<Button>("BackTasks").Visibility=Visibility.Collapsed;save.Content="Save project limits";
            var fields=Find<StackPanel>("ContextSettings");var old=(Expander)current.Parent;old.Content=null;fields.Children.Remove(old);fields.Children.Insert(0,current);
            foreach(var help in fields.Children.OfType<Expander>())help.Visibility=Visibility.Collapsed;
        }
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
            current.Text="Saved: "+Format.Limit(baseline.Saved.Window)+" | Compact: "+Format.Limit(baseline.Saved.Compact)+"\nLive: "+Format.Limit(baseline.Live)+" | "+baseline.Model;
            baseLabel.Text="Base: "+Format.Tokens(baseline.Base)+" ("+baseline.Source+")";baseLabel.ToolTip=path;result.Text="";save.IsEnabled=true;
            current.ToolTip="File: "+path+"\nApplies to all models in this scope.\nLocal model capacity: "+Format.Tokens(baseline.Catalog?.Maximum);
        }
        catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException){baseline=null;result.Text=e.Message;save.IsEnabled=false;}
        Hint();
    }
    private void Hint()
    {
        try{var v=ContextSettings.Draft(window.Text,compact.Text);bool changed=baseline!=null&&v!=baseline.Saved;
            hint.Text=v.Window.HasValue&&v.Compact.HasValue?$"{100d*v.Compact/v.Window:N1}% = {Format.Tokens(v.Compact)} tokens. "+(changed?"Select Save to store these values.":"These values are saved."):"Example: 90% of 200k = 180k. CTC saves the percentage as tokens.";
            if(baseline?.Catalog?.Maximum is { } maximum&&v.Window>maximum)hint.Text+=" This value exceeds local model capacity.";
            if(baseline!=null)save.IsEnabled=changed;}
        catch(ArgumentException e){hint.Text=e.Message;if(save!=null)save.IsEnabled=false;}
    }
    private void Scale(int n)
    {
        try{if(baseline?.Base==null&&baseline!=null)baseline=baseline with{Base=ContextSettings.Parse(window.Text),Source="entered window"};var v=ContextSettings.Scale(baseline?.Base,n,window.Text,compact.Text);window.Text=v.Window;compact.Text=v.Compact;result.Text="";baseLabel.Text="Base: "+Format.Tokens(baseline?.Base)+" ("+baseline?.Source+")";}
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
