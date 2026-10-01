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
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CTC.Core;

namespace CTC.App;
public static class UiChecks
{
    private static IEnumerable<T> Find<T>(DependencyObject parent) where T:DependencyObject
    {if(parent is T item)yield return item;for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++)foreach(var child in Find<T>(VisualTreeHelper.GetChild(parent,i)))yield return child;}
    private static T Id<T>(Window window,string id) where T:DependencyObject
    {window.UpdateLayout();return Find<T>(window).FirstOrDefault(x=>AutomationProperties.GetAutomationId(x)==id)??throw new InvalidOperationException("Missing control: "+id);}
    private static async Task Click(Window window,string id){Id<Button>(window,id).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Task.Delay(100);}
    private static void Capture(Window window,string path)
    {
        window.UpdateLayout();var dpi=VisualTreeHelper.GetDpi(window);
        var image=new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth*dpi.DpiScaleX),(int)Math.Ceiling(window.ActualHeight*dpi.DpiScaleY),96*dpi.DpiScaleX,96*dpi.DpiScaleY,PixelFormats.Pbgra32);image.Render(window);
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(image));using var stream=File.Create(path);encoder.Save(stream);
    }
    public static async Task Run(WidgetWindow window,string home,string data,string output)
    {
        Directory.CreateDirectory(output);var checks=new List<string>();var stopwatch=Stopwatch.StartNew();
        void Check(bool value,string name){if(!value)throw new InvalidOperationException(name);checks.Add(name);}
        try
        {
            for(int i=0;i<100&&!Find<TextBlock>(window).Any(t=>t.Text.Contains("Fixture chat"));i++)await Task.Delay(100);
            Check(Find<TextBlock>(window).Any(t=>t.Text.Contains("Fixture chat")),"First fixture chat appears");
            Check(window.Width==370&&window.Height==88,"Parked default");Capture(window,Path.Combine(output,"parked.png"));
            await Click(window,"RestoreBar");Capture(window,Path.Combine(output,"context-compact.png"));await Click(window,"EditContextLimits");
            Check(window.Width==370&&window.Height==480,"Parked limits opens at compact size");
            var windowField=Id<TextBox>(window,"WindowInput");var compactField=Id<TextBox>(window,"CompactInput");
            var windowPoint=windowField.TransformToAncestor(window).Transform(new Point());var compactPoint=compactField.TransformToAncestor(window).Transform(new Point());
            Check(Math.Abs(windowPoint.Y-compactPoint.Y)<1&&compactPoint.X>windowPoint.X+100,"Original two-column limit fields");
            Check(!Id<Button>(window,"SaveLimits").IsEnabled,"Unchanged limits disable Save");
            Id<TextBox>(window,"WindowInput").Text="200k";Id<TextBox>(window,"CompactInput").Text="90%";
            await Click(window,"Scale2");Check(Id<TextBox>(window,"WindowInput").Text=="400000"&&Id<TextBox>(window,"CompactInput").Text=="90%","Scale keeps percentage");
            await Click(window,"Scale3");Check(Id<TextBox>(window,"WindowInput").Text=="600000","Scaler anchors to base");
            double oldLeft=window.Left,oldTop=window.Top;
            await Click(window,"Expand");window.Left+=45;window.Top+=30;
            Check(Id<TextBox>(window,"WindowInput").Text=="600000","Expansion keeps draft");Capture(window,Path.Combine(output,"limits-expanded.png"));
            await Click(window,"Expand");Check(Math.Abs(window.Left-oldLeft)<1&&Math.Abs(window.Top-oldTop)<1,"Collapse restores corner");
            await Click(window,"SaveLimits");
            string path=Path.Combine(home,"project",".codex","config.toml");Check(ContextSettings.ReadLimits(path)==new LimitValues(600000,540000),"Actual UI saves percentage");
            Check(new QueueStore(Path.Combine(data,"limits-queue.json"),home).Read().Length==1,"Actual UI queues save");Capture(window,Path.Combine(output,"limits-compact.png"));
            await Click(window,"QueueMode");Check(!Id<Button>(window,"RestartNow").IsEnabled,"Busy chat disables restart now");Capture(window,Path.Combine(output,"queue.png"));
            await Click(window,"TokensMode");
            Check(!Find<Button>(window).Any(b=>b.Content?.ToString()=="Limits"&&b.IsVisible),"Limits stays under Context");
            Id<Expander>(window,"breakdown").IsExpanded=true;window.UpdateLayout();Id<Expander>(window,"tools").IsExpanded=true;Id<Expander>(window,"exec").IsExpanded=true;Id<Expander>(window,"commands").IsExpanded=true;window.UpdateLayout();Capture(window,Path.Combine(output,"tokens-compact.png"));
            var scroll=Find<ScrollViewer>(window).First(x=>x.ScrollableHeight>0);scroll.ScrollToVerticalOffset(50);window.UpdateLayout();double offset=scroll.VerticalOffset;
            scroll.RaiseEvent(new System.Windows.Input.MouseWheelEventArgs(System.Windows.Input.Mouse.PrimaryDevice,Environment.TickCount,-120){RoutedEvent=System.Windows.Input.Mouse.PreviewMouseWheelEvent});
            await Task.Delay(100);window.UpdateLayout();
            Check(Math.Abs(scroll.VerticalOffset-offset-24)<2,"Wheel uses 24 pixel steps");
            await Click(window,"Expand");Capture(window,Path.Combine(output,"tokens-expanded.png"));
            // Capture user-guide examples with the title visible and secondary details closed.
            Id<Expander>(window,"breakdown").IsExpanded=false;scroll.ScrollToTop();await Task.Delay(100);
            Capture(window,Path.Combine(output,"tokens-overview.png"));
            Id<Expander>(window,"breakdown").IsExpanded=true;Id<Expander>(window,"tools").IsExpanded=false;
            double screenshotHeight=window.Height;window.Height=840;scroll.ScrollToTop();await Task.Delay(100);
            Capture(window,Path.Combine(output,"tokens-breakdown.png"));window.Height=screenshotHeight;
            await Click(window,"ContextMode");Id<Slider>(window,"BackgroundOpacity").Value=85;Capture(window,Path.Combine(output,"context.png"));
            var inline=Id<Expander>(window,"fixture-chatedit");inline.IsExpanded=true;window.UpdateLayout();
            Check(Id<TextBox>(window,"WindowInput").IsVisible,"Original inline project editor");Capture(window,Path.Combine(output,"context-inline.png"));
            inline.IsExpanded=false;await Click(window,"Expand");Capture(window,Path.Combine(output,"context-return.png"));
            await Click(window,"Minimize");Check(window.Height==88,"Minimize returns parked bar");
            await Click(window,"RestoreBar");await Click(window,"Tray");Check(!window.IsVisible,"Tray hides widget");window.Restore();Check(window.IsVisible,"Tray restore");
            await Click(window,"AppSettings");Capture(window,Path.Combine(output,"app-settings.png"));
            Check(Find<TextBlock>(window).Any(t=>t.Text=="Window and startup"),"Original app settings page");
            await Click(window,"ContextMode");
            var setup=new SetupWindow(data,true);setup.Show();await Task.Delay(100);Capture(setup,Path.Combine(output,"setup.png"));
            Check(setup.Width==600&&setup.Height==550,"Original setup dimensions");
            await Click(setup,"SetupNext");Capture(setup,Path.Combine(output,"setup-options.png"));
            Check(Id<Button>(setup,"SetupNext").Content?.ToString()=="Install","Original setup options");
            await Click(setup,"SetupNext");Check(Id<Button>(setup,"SetupNext").Content?.ToString()=="Finish","Actual setup wizard fixture install");Capture(setup,Path.Combine(output,"setup-done.png"));setup.Close();
            string closed=Path.Combine(output,"normally-closed.txt");
            var start=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
            foreach(string arg in new[]{"--desktop-fixture",closed,"--data",Path.Combine(output,"child-data")})start.ArgumentList.Add(arg);
            using(var child=Process.Start(start)!)
            {
                try
                {
                    for(int i=0;i<100&&DesktopIdentity.VisibleWindows(child.Id)==0;i++)await Task.Delay(50);
                    Check(DesktopIdentity.VisibleWindows(child.Id)>0,"Marked desktop fixture owns a window");
                    Check(DesktopIdentity.CloseNormally(new(child.Id,Environment.ProcessPath!)),"Normal close reaches selected window");
                    using var timeout=new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(10));await child.WaitForExitAsync(timeout.Token);
                    Check(File.Exists(closed)&&File.ReadAllText(closed)=="Closed normally","Native normal close does not force exit");
                }
                finally{if(!child.HasExited)child.Kill(true);}
            }
            var installed=Path.Combine(output,"install fixture");Installer.Install(installed,AppContext.BaseDirectory,data,false,false);
            Check(File.Exists(Path.Combine(Installer.ReadInstallation(installed)!.Current,"ContextTokenCodex.exe")),"Compiled setup isolated install");
            Check(File.Exists(Path.Combine(Installer.ReadInstallation(installed)!.Current,"de","PresentationFramework.resources.dll")),"Compiled setup keeps locale files");
            Installer.Install(installed,AppContext.BaseDirectory,data,false,false);
            Check(Directory.Exists(Installer.ReadInstallation(installed)!.Previous),"Compiled update preserves previous version");
            string previousVersion=Installer.ReadInstallation(installed)!.Previous;
            Installer.Rollback(installed,false);Check(Installer.ReadInstallation(installed)!.Current==previousVersion,"Compiled rollback changes current version");
            using(var pointer=JsonDocument.Parse(File.ReadAllText(Path.Combine(data,"native-installation.json"))))Check(pointer.RootElement.Text("Executable")==Path.Combine(previousVersion,"ContextTokenCodex.exe"),"Rollback changes watcher pointer");
            Installer.Uninstall(previousVersion,data);Check(Directory.Exists(previousVersion)&&File.Exists(Path.Combine(data,"overlay.json"))&&File.Exists(Path.Combine(data,"native-uninstalled.json")),"Uninstall retains versions and preferences");
            Check(File.Exists(Path.Combine(data,"overlay.json")),"Compiled setup preserves preferences");
            Check(!File.Exists(Path.Combine(data,"native-errors.log")),"No native runtime errors");
            using(var p=Process.GetCurrentProcess())AtomicFile.Json(Path.Combine(output,"checks.json"),new{Passed=checks.Count,Checks=checks,Seconds=stopwatch.Elapsed.TotalSeconds,WorkingSetBytes=p.WorkingSet64,PrivateBytes=p.PrivateMemorySize64,Threads=p.Threads.Count,Runtime=Environment.Version.ToString()});
            window.Close();
        }
        catch(Exception e){AtomicFile.Json(Path.Combine(output,"checks.json"),new{Passed=checks.Count,Checks=checks,Error=e.ToString()});window.Close();}
    }
}
