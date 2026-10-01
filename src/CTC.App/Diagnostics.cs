// SPDX-License-Identifier: MIT
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using CTC.Core;

namespace CTC.App;
public static class Diagnostics
{
    public static async Task Run(string home,string data,string output)
    {
        using var monitor=new MonitorService(home);var time=Stopwatch.StartNew();var first=monitor.Read();double firstSeconds=time.Elapsed.TotalSeconds;
        var snapshots=first;
        for(int i=0;i<4;i++){await Task.Delay(1000);snapshots=monitor.Read();}
        string quotaError="";QuotaSnapshot? quota=null;double quotaSeconds=0;
        try{time.Restart();quota=await new QuotaProvider(home,data).ReadAsync();quotaSeconds=time.Elapsed.TotalSeconds;}
        catch(Exception e) when(e is IOException or TimeoutException or System.ComponentModel.Win32Exception){quotaError=e.Message;}
        using var process=Process.GetCurrentProcess();
        AtomicFile.Json(output,new{FirstSnapshotSeconds=firstSeconds,RecordedChats=snapshots.Chats.Length,ActiveChats=snapshots.ActiveChats.Length,Projects=snapshots.Projects.Length,
            ContextRecords=snapshots.Chats.Count(c=>c.Window.HasValue),TokenRecords=snapshots.Chats.Count(c=>c.Total.Total.HasValue),ReadErrors=snapshots.Chats.Count(c=>c.Error.Length>0),
            snapshots.DiscoveryComplete,snapshots.LifecycleComplete,snapshots.Warning,QuotaSeconds=quotaSeconds,QuotaWindows=quota?.Windows.Select(w=>new{w.Label,w.Used,w.Remaining}),QuotaSource=quota?.Source,QuotaError=quotaError,
            WorkingSetBytes=process.WorkingSet64,PrivateBytes=process.PrivateMemorySize64,Threads=process.Threads.Count,Runtime=Environment.Version.ToString(),Architecture=System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString()});
    }
}
