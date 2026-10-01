// SPDX-License-Identifier: MIT
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using CTC.Core;
using static CTC.App.Controls;

namespace CTC.App;
public static class Installer
{
    public static string DefaultFolder=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","Context-Token-Codex");
    public static void Install(string destination,string source,string data,bool startup,bool shortcuts=true)
    {
        destination=Path.GetFullPath(destination);source=Path.GetFullPath(source);
        if(destination.TrimEnd(Path.DirectorySeparatorChar).Equals(Path.GetPathRoot(destination),StringComparison.OrdinalIgnoreCase))throw new IOException("Choose an app folder. Do not select a drive root.");
        if(destination.Equals(source,StringComparison.OrdinalIgnoreCase))throw new IOException("Choose a folder outside the extracted release.");
        string[] required=["ContextTokenCodex.exe","ContextTokenCodex.dll","LICENSE","THIRD_PARTY_NOTICES.md","Quota.Rates.json","native-files.json","DOTNET-LICENSE.txt","DOTNET-THIRD-PARTY-NOTICES.txt"];
        foreach(string file in required)if(!File.Exists(Path.Combine(source,file)))throw new IOException("The release has no "+file+". Download the complete release.");
        var manifest=JsonSerializer.Deserialize<Manifest>(File.ReadAllText(Path.Combine(source,"native-files.json")),AtomicFile.Options);
        if(manifest?.Schema!=1||manifest.Files==null||manifest.Files.Count>2048)throw new IOException("The release file list is incorrect.");
        string sourcePrefix=source.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;long totalBytes=0;
        foreach(var pair in manifest.Files)
        {
            string resolved=Path.GetFullPath(Path.Combine(source,pair.Key));
            if(!resolved.StartsWith(sourcePrefix,StringComparison.OrdinalIgnoreCase)||pair.Key.Split('/','\\').Any(x=>x is "." or "..")||Path.IsPathFullyQualified(pair.Key))throw new IOException("The release contains an incorrect file path.");
            var file=new FileInfo(resolved);
            if(!file.Exists||(file.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("A release file is unavailable.");
            totalBytes+=file.Length;if(totalBytes>256*1024*1024)throw new IOException("The release is too large.");
            using var stream=File.OpenRead(resolved);
            if(!Convert.ToHexString(SHA256.HashData(stream)).Equals(pair.Value,StringComparison.OrdinalIgnoreCase))throw new IOException("A release file changed. Download the complete release again.");
        }
        if(required.Where(f=>f!="native-files.json").Any(f=>!manifest.Files.ContainsKey(f)))throw new IOException("The release file list is incomplete.");
        Directory.CreateDirectory(destination);
        string versions=Path.Combine(destination,"Versions");
        string version=typeof(Installer).Assembly.GetName().Version?.ToString(3)??"7.0.0";
        string target=Path.Combine(versions,version);
        if(Directory.Exists(target))target+="-"+DateTime.Now.ToString("yyyyMMddHHmmss")+"-"+Guid.NewGuid().ToString("N")[..6];
        string staging=target+".staging-"+Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(staging);
        try
        {
            foreach(string name in manifest.Files.Keys.Append("native-files.json"))
            {
                string targetFile=Path.Combine(staging,name);Directory.CreateDirectory(Path.GetDirectoryName(targetFile)!);
                File.Copy(Path.Combine(source,name),targetFile);
            }
            Directory.Move(staging,target);
            var old=ReadInstallation(destination);
            AtomicFile.Json(Path.Combine(destination,"installation.json"),new Installation(2,version,target,old?.Current??"",data,DateTimeOffset.Now),true);
            string executable=Path.Combine(target,"ContextTokenCodex.exe");
            if(shortcuts)
            {
                string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                string programs=Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                Shortcut(Path.Combine(desktop,"Context-Token Codex.lnk"),executable,"",target);
                Shortcut(Path.Combine(programs,"Context-Token Codex.lnk"),executable,"",target);
                SetStartup(target,data,startup);
            }
            var prefs=Preferences.Load(Path.Combine(data,"overlay.json"));prefs.AutoOpen=startup;AtomicFile.Json(Path.Combine(data,"overlay.json"),prefs,true);
            AtomicFile.Json(Path.Combine(data,"native-installation.json"),new{Folder=destination,Version=version,Executable=executable});
            string uninstalled=Path.Combine(data,"native-uninstalled.json");if(File.Exists(uninstalled))File.Delete(uninstalled);
        }
        catch{if(Directory.Exists(staging))Directory.Delete(staging,true);throw;}
    }
    public sealed record Installation(int Schema,string Version,string Current,string Previous,string Data,DateTimeOffset Installed);
    private sealed record Manifest(int Schema,Dictionary<string,string> Files);
    public static Installation? ReadInstallation(string folder)
    {string path=Path.Combine(folder,"installation.json");try{return File.Exists(path)?JsonSerializer.Deserialize<Installation>(File.ReadAllText(path),AtomicFile.Options):null;}catch(JsonException){return null;}}
    public static void Launch(string folder)
    {var i=ReadInstallation(folder)??throw new IOException("The installation record is unavailable.");Process.Start(new ProcessStartInfo(Path.Combine(i.Current,"ContextTokenCodex.exe")){UseShellExecute=true});}
    public static void SetStartup(string folder,string data,bool enabled)
    {
        string startup=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"Context-Token Codex.lnk");
        if(!enabled){if(File.Exists(startup))File.Delete(startup);return;}
        Shortcut(startup,Path.Combine(folder,"ContextTokenCodex.exe"),"--watch --data \""+data+"\"",folder);
    }
    public static void StartWatcher(string folder,string data)
    {
        var p=new ProcessStartInfo(Path.Combine(folder,"ContextTokenCodex.exe")){UseShellExecute=false,CreateNoWindow=true};
        p.ArgumentList.Add("--watch");p.ArgumentList.Add("--data");p.ArgumentList.Add(data);Process.Start(p);
    }
    private static void Shortcut(string path,string executable,string arguments,string workingDirectory)
    {
        Type type=Type.GetTypeFromProgID("WScript.Shell")??throw new IOException("Windows shortcut services are unavailable.");
        object shell=Activator.CreateInstance(type)!;object? link=null;
        try
        {
            link=type.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,[path])!;
            void Set(string property,object value)=>link.GetType().InvokeMember(property,BindingFlags.SetProperty,null,link,[value]);
            Set("TargetPath",executable);Set("Arguments",arguments);Set("WorkingDirectory",workingDirectory);Set("IconLocation",executable+",0");Set("Description","Context-Token Codex");Set("WindowStyle",1);
            link.GetType().InvokeMember("Save",BindingFlags.InvokeMethod,null,link,null);
        }
        finally{if(link!=null)Marshal.FinalReleaseComObject(link);Marshal.FinalReleaseComObject(shell);}
    }
    public static void Rollback(string folder,bool shortcuts=true)
    {
        var i=ReadInstallation(folder)??throw new IOException("The installation record is unavailable.");
        if(!Directory.Exists(i.Previous))throw new IOException("No earlier compiled version is available. Use the PowerShell 6.8.9 release.");
        string version=AssemblyName.GetAssemblyName(Path.Combine(i.Previous,"ContextTokenCodex.dll")).Version?.ToString(3)??"unknown";
        AtomicFile.Json(Path.Combine(folder,"installation.json"),i with{Version=version,Current=i.Previous,Previous=i.Current},true);
        string executable=Path.Combine(i.Previous,"ContextTokenCodex.exe");
        if(shortcuts)
        {
            Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"Context-Token Codex.lnk"),executable,"",i.Previous);
            Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"Context-Token Codex.lnk"),executable,"",i.Previous);
            SetStartup(i.Previous,i.Data,Preferences.Load(Path.Combine(i.Data,"overlay.json")).AutoOpen);
        }
        AtomicFile.Json(Path.Combine(i.Data,"native-installation.json"),new{Folder=folder,Version=version,Executable=executable});
    }
    public static void Uninstall(string current,string data)
    {
        // Keep versions and user settings. Only remove shortcuts owned by this app.
        string pointer=Path.Combine(data,"native-installation.json"),root=current;
        if(File.Exists(pointer)){using var doc=JsonDocument.Parse(File.ReadAllText(pointer));root=doc.RootElement.Text("Folder");}
        foreach(string folder in new[]{Environment.GetFolderPath(Environment.SpecialFolder.Startup),Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),Environment.GetFolderPath(Environment.SpecialFolder.Programs)})
        {string path=Path.Combine(folder,"Context-Token Codex.lnk");if(File.Exists(path)&&OwnedShortcut(path,root))File.Delete(path);}
        var prefs=Preferences.Load(Path.Combine(data,"overlay.json"));prefs.AutoOpen=false;AtomicFile.Json(Path.Combine(data,"overlay.json"),prefs,true);
        AtomicFile.Json(Path.Combine(data,"native-uninstalled.json"),new{At=DateTimeOffset.Now,Current=current});
    }
    private static bool OwnedShortcut(string path,string root)
    {
        if(!Path.IsPathFullyQualified(root))return false;
        Type type=Type.GetTypeFromProgID("WScript.Shell")??throw new IOException("Windows shortcut services are unavailable.");
        object shell=Activator.CreateInstance(type)!;object? link=null;
        try
        {
            link=type.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,[path])!;
            string target=link.GetType().InvokeMember("TargetPath",BindingFlags.GetProperty,null,link,null) as string??"";
            return target.StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)&&Path.GetFileName(target).Equals("ContextTokenCodex.exe",StringComparison.OrdinalIgnoreCase);
        }
        finally{if(link!=null)Marshal.FinalReleaseComObject(link);Marshal.FinalReleaseComObject(shell);}
    }
}
public sealed class SetupWindow:Window
{
    public SetupWindow(string data)
    {
        Title="Context-Token Codex setup";Width=570;Height=460;WindowStartupLocation=WindowStartupLocation.CenterScreen;Background=Ink;FontFamily=new System.Windows.Media.FontFamily("Segoe UI");
        Icon=System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/ContextTokenCodex;component/Assets/Context.ico"));
        var p=new StackPanel{Margin=new Thickness(24)};Content=p;
        var logo=Label("ctc",36);logo.FontWeight=FontWeights.SemiBold;p.Children.Add(logo);p.Children.Add(Label("Install Context-Token Codex",22));
        p.Children.Add(Label("C# and WPF · Version 7.0.0",11,true));
        p.Children.Add(Label("Earlier versions and settings remain available. This version requires Windows 10 or Windows 11.",12));
        p.Children.Add(Label("App folder",11,true));
        var folder=new TextBox{Text=Installer.DefaultFolder,Padding=new Thickness(8),Margin=new Thickness(0,4,0,8)};p.Children.Add(folder);
        var startup=new CheckBox{Content="Auto-open with app at Windows sign-in",IsChecked=true,Margin=new Thickness(0,10,0,10)};p.Children.Add(startup);
        var result=Label("",11);p.Children.Add(result);
        var install=Button("Install",()=>
        {
            try
            {
                Installer.Install(folder.Text,AppContext.BaseDirectory,data,startup.IsChecked==true);
                var record=Installer.ReadInstallation(folder.Text)!;
                if(startup.IsChecked==true)Installer.StartWatcher(record.Current,data);
                Installer.Launch(folder.Text);result.Text="Installation complete. CTC is open.";Close();
            }
            catch(Exception e) when(e is IOException or UnauthorizedAccessException or COMException){result.Text=e.Message;}
        },"Install the compiled widget.");
        p.Children.Add(install);p.Children.Add(Button("Cancel",Close));p.Children.Add(Label("Yahya Nabil · MIT License",10,true));
    }
}
