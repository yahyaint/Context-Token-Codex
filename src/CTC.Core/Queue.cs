// SPDX-License-Identifier: MIT
using System.Text.Json;

namespace CTC.Core;

public sealed record LimitsQueue(int Version,QueueEntry[] Entries);
public sealed class QueueStore(string path,string home)
{
    public QueueEntry[] Read()
    {
        if(!File.Exists(path))return [];
        if(new FileInfo(path).Length>1024*1024)throw new InvalidDataException("The queue is too large. Keep the file for repair.");
        var queue=JsonSerializer.Deserialize<LimitsQueue>(File.ReadAllText(path),AtomicFile.Options);
        if(queue?.Version!=1||queue.Entries==null)throw new InvalidDataException("CTC cannot read this queue format. Keep the file for repair.");
        foreach(var e in queue.Entries)
            if(e==null||string.IsNullOrWhiteSpace(e.Path)||!Path.IsPathFullyQualified(e.Path)||e.Window is <1||e.Compact is <1||e.Window.HasValue&&e.Compact>e.Window)
                throw new InvalidDataException("A queue limit or path is incorrect. Keep the file for repair.");
        return queue.Entries;
    }
    public void Save(string config,LimitValues values)
    {
        var entries=Read().Where(x=>!string.Equals(x.Path,Path.GetFullPath(config),StringComparison.OrdinalIgnoreCase)).ToList();
        entries.Add(new(Path.GetFullPath(config),values.Window,values.Compact,DateTimeOffset.UtcNow));
        AtomicFile.Json(path,new LimitsQueue(1,entries.ToArray()));
    }
    public QueueView[] Views(ChatView[] chats)
    {
        var catalog=new ModelCatalog(home);
        return Read().Select(e=>
        {
            string error="",status="Saved. A fresh Codex session is required.";bool changed=false;
            ChatView[] related=[];
            try
            {
                changed=ContextSettings.ReadLimits(e.Path)!=new LimitValues(e.Window,e.Compact);
                related=chats.Where(c=>ContextSettings.ConfigPaths(home,c.Cwd).Contains(e.Path,StringComparer.OrdinalIgnoreCase)&&
                    !ContextSettings.ConfigPaths(home,c.Cwd).TakeWhile(p=>!p.Equals(e.Path,StringComparison.OrdinalIgnoreCase)).Any(p=>ContextSettings.ReadLimits(p).Window.HasValue)).ToArray();
                if(changed)status="The file changed after Save.";
                else if(e.Window.HasValue&&related.Length>0&&related.All(c=>c.UsageAt>=e.SavedAt&&catalog.Find(c.Model)?.UsablePercent is { } percent&&c.Window==(long)Math.Floor(e.Window.Value*percent/100)))
                    status="Recorded window matches. The compaction threshold is not confirmed.";
            }
            catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or InvalidDataException){error=ex.Message;status="CTC cannot read the current settings.";}
            return new QueueView(e,changed,error,status,related.Select(c=>c.Title).ToArray());
        }).ToArray();
    }
}

public static class RestartGate
{
    public static string Reason(MonitorSnapshot snapshot) => !snapshot.LifecycleComplete?"CTC cannot verify all chat records.":snapshot.Chats.Any(x=>x.Active)?"CTC waits for running chats to stop.":"Recorded chats are idle.";
    public static bool Ready(MonitorSnapshot snapshot)=>snapshot.LifecycleComplete&&!snapshot.Chats.Any(x=>x.Active);
}
public sealed class RestartController(string statusPath)
{
    public RestartStatus? Read()
    {try{return File.Exists(statusPath)?JsonSerializer.Deserialize<RestartStatus>(File.ReadAllText(statusPath),AtomicFile.Options):null;}catch(JsonException){return null;}catch(IOException){return null;}}
    public void Request()
    {
        var old=Read();
        if(old?.Status is "Waiting" or "Closing")return;
        AtomicFile.Json(statusPath,new RestartStatus("Waiting","CTC waits for running chats to stop.",DateTimeOffset.UtcNow.AddHours(24),DateTimeOffset.Now));
    }
    public void Cancel()
    {var s=Read();AtomicFile.Json(statusPath,new RestartStatus("Cancelled","The restart request was cancelled.",s?.ExpiresAt??DateTimeOffset.Now,DateTimeOffset.Now));}
    private void Set(string status,string message,RestartStatus s)=>AtomicFile.Json(statusPath,s with{Status=status,Message=message,Updated=DateTimeOffset.Now});
    public async Task RunAsync(MonitorService monitor,CancellationToken token=default)
    {
        DateTimeOffset? idle=null;
        while(!token.IsCancellationRequested)
        {
            var s=Read();if(s?.Status!="Waiting")return;
            if(s.ExpiresAt==default||DateTimeOffset.Now>=s.ExpiresAt){Set("Expired","The restart request expired. Select a restart button again.",s);return;}
            var snapshot=monitor.Read();
            if(!RestartGate.Ready(snapshot))idle=null;
            else idle??=DateTimeOffset.Now;
            if(idle!=null&&DateTimeOffset.Now-idle>=TimeSpan.FromSeconds(10))
            {
                var desktop=DesktopIdentity.Find("Codex",true);
                if(desktop.Length==0){Set("Blocked","Codex is not open. Open Codex to load the saved settings.",s);return;}
                string launch=desktop[0].Path;
                if(!RestartGate.Ready(monitor.Read())){idle=null;continue;}
                var confirmed=Read();if(confirmed?.Status!="Waiting"||confirmed.ExpiresAt!=s.ExpiresAt||DateTimeOffset.Now>=confirmed.ExpiresAt)return;
                Set("Closing","CTC requested a normal close. Open Codex windows will close.",s);
                if(Read()?.Status!="Closing")return;
                if(desktop.Any(p=>!DesktopIdentity.CloseNormally(p))){Set("Blocked","A Codex window did not accept normal close. Quit Codex manually.",s);return;}
                var deadline=DateTimeOffset.Now.AddSeconds(45);
                while(DateTimeOffset.Now<deadline&&DesktopIdentity.Find("Codex").Length>0)
                {if(Read()?.Status=="Cancelled")return;await Task.Delay(500,token);}
                if(DesktopIdentity.Find("Codex").Length>0){Set("Blocked","Codex did not close. CTC did not force the close.",s);return;}
                if(Read()?.Status=="Cancelled")return;
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(launch){UseShellExecute=true});
                Set("Reopened","Codex reopened. Resume the chat. Check the next context record.",s);return;
            }
            await Task.Delay(1000,token);
        }
    }
}
