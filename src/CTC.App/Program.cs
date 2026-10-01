// SPDX-License-Identifier: MIT
using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using CTC.Core;

namespace CTC.App;

public static class Program
{
    public static string Option(string[] args,string name,string fallback="")
    {int i=Array.IndexOf(args,name);return i>=0&&i+1<args.Length?args[i+1]:fallback;}
    public static string DefaultData => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexContextMonitor");
    [STAThread]
    public static int Main(string[] args)
    {
        string data=Option(args,"--data",DefaultData);
        string home=Option(args,"--home",Environment.GetEnvironmentVariable("CODEX_HOME")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".codex"));
        Directory.CreateDirectory(data);
        try
        {
            if(Array.IndexOf(args,"--ui-test")>=0)
            {
                string output=Path.GetFullPath(Option(args,"--ui-test"));
                if(!Path.GetFullPath(home).Equals(Path.Combine(output,"home"),StringComparison.OrdinalIgnoreCase)||
                    !Path.GetFullPath(data).Equals(Path.Combine(output,"data"),StringComparison.OrdinalIgnoreCase)||!File.Exists(Path.Combine(output,"ctc-native-ui.fixture")))
                    throw new IOException("Use an isolated UI fixture folder. CTC did not run the UI checks.");
            }
            if(Array.IndexOf(args,"--diagnostics")>=0){Diagnostics.Run(home,data,Option(args,"--diagnostics")).GetAwaiter().GetResult();return 0;}
            if(Array.IndexOf(args,"--watch")>=0){Watch(data,home,Array.IndexOf(args,"--takeover")>=0);return 0;}
            if(Array.IndexOf(args,"--restart-helper")>=0)
            {
                using var mutex=new Mutex(true,"Local\\CTC-Restart-"+Scope(data),out bool owned);
                if(!owned)return 0;
                using var monitor=new MonitorService(home);
                new RestartController(Path.Combine(data,"restart.json")).RunAsync(monitor).GetAwaiter().GetResult();return 0;
            }
            if(Array.IndexOf(args,"--install")>=0){Installer.Install(Option(args,"--install"),AppContext.BaseDirectory,data,!Array.Exists(args,x=>x=="--no-startup"));return 0;}
            if(Array.IndexOf(args,"--uninstall")>=0){Installer.Uninstall(AppContext.BaseDirectory,data);return 0;}
            if(Array.IndexOf(args,"--rollback")>=0){Installer.Rollback(Option(args,"--rollback"));return 0;}
            if(Array.IndexOf(args,"--desktop-fixture")>=0)
            {
                var fixtureApp=new Application();var fixtureWindow=new Window{Title="CTC marked restart fixture",Width=280,Height=140,Content="Fixture window"};
                fixtureWindow.Closed+=(_,_)=>File.WriteAllText(Option(args,"--desktop-fixture"),"Closed normally");fixtureApp.Run(fixtureWindow);return 0;
            }
            var app=new Application{ShutdownMode=ShutdownMode.OnMainWindowClose};
            app.Resources.MergedDictionaries.Add(new ResourceDictionary{Source=new Uri("/ContextTokenCodex;component/Theme.xaml",UriKind.Relative)});
            app.DispatcherUnhandledException+=(s,e)=>{Log(data,e.Exception);MessageBox.Show("CTC could not complete this action. Check native-errors.log.","Context-Token Codex");e.Handled=true;};
            if(Array.IndexOf(args,"--setup")>=0||string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath),"Setup",StringComparison.OrdinalIgnoreCase)){app.Run(new SetupWindow(data));return 0;}
            using var instance=new Mutex(true,"Local\\CTC-Widget-"+Scope(data),out bool first);
            using var restore=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\CTC-Restore-"+Scope(data));
            if(!first){restore.Set();return 0;}
            var window=new WidgetWindow(home,data,args);
            var wait=ThreadPool.RegisterWaitForSingleObject(restore,(_,timedOut)=>{if(!timedOut)app.Dispatcher.BeginInvoke(()=>window.Restore());},null,Timeout.Infinite,false);
            try{app.Run(window);}finally{wait.Unregister(null);}
            return 0;
        }
        catch(Exception e){Log(data,e);return 1;}
    }
    public static void Log(string data,Exception error)
    {try{File.AppendAllText(Path.Combine(data,"native-errors.log"),DateTimeOffset.Now+" "+error.GetType().Name+": "+error.Message+Environment.NewLine);}catch(IOException){}}
    private static string Scope(string path)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToLowerInvariant())))[..20];
    private static void Watch(string data,string home,bool takeover)
    {
        using var mutex=new Mutex(false,"Local\\CTC-Watch-"+Scope(data));
        bool owned;try{owned=mutex.WaitOne(takeover?15000:0);}catch(AbandonedMutexException){owned=true;}if(!owned)return;
        bool wasOpen=false;DateTimeOffset retry=default,opened=DateTimeOffset.Now;
        try{while(true)
        {
            if(File.Exists(Path.Combine(data,"native-uninstalled.json")))return;
            string pointer=Path.Combine(data,"native-installation.json");
            if(File.Exists(pointer)&&new FileInfo(pointer).Length<65536)
            {
                try
                {
                    using var doc=System.Text.Json.JsonDocument.Parse(File.ReadAllText(pointer));
                    string newer=doc.RootElement.Text("Executable"),folder=doc.RootElement.Text("Folder");
                    if(Path.IsPathFullyQualified(newer)&&Path.IsPathFullyQualified(folder)&&
                        newer.StartsWith(Path.Combine(folder,"Versions")+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)&&
                        Path.GetFileName(newer)=="ContextTokenCodex.exe"&&File.Exists(newer)&&!newer.Equals(Environment.ProcessPath,StringComparison.OrdinalIgnoreCase))
                    {
                        var replacement=new ProcessStartInfo(newer){UseShellExecute=false,CreateNoWindow=true};
                        foreach(string arg in new[]{"--watch","--takeover","--data",data,"--home",home})replacement.ArgumentList.Add(arg);
                        Process.Start(replacement);return;
                    }
                }catch(System.Text.Json.JsonException){}
            }
            var prefs=Preferences.Load(Path.Combine(data,"overlay.json"));
            bool open=prefs.AutoOpen&&DesktopIdentity.Find(prefs.Target,true).Length>0;
            if(open&&!wasOpen)opened=DateTimeOffset.Now;
            string closed=Path.Combine(data,"manual-close.txt");
            bool manuallyClosed=File.Exists(closed)&&File.GetLastWriteTimeUtc(closed)>=opened.UtcDateTime;
            if(open&&!manuallyClosed&&(!wasOpen||DateTimeOffset.Now>=retry))
            {
                try
                {
                    using var widget=Mutex.OpenExisting("Local\\CTC-Widget-"+Scope(data));
                    // An existing widget remains in its selected view.
                }
                catch(WaitHandleCannotBeOpenedException)
                {
                    var start=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
                    foreach(string a in new[]{"--data",data,"--home",home})start.ArgumentList.Add(a);
                    Process.Start(start);
                }
                retry=DateTimeOffset.Now.AddSeconds(15);
            }
            wasOpen=open;Thread.Sleep(2000);
        }}finally{mutex.ReleaseMutex();}
    }
}
