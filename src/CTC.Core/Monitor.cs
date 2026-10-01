// SPDX-License-Identifier: MIT
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CTC.Core;

public sealed class MonitorService(string home):IDisposable
{
    private sealed class Track
    {
        public SessionTail Tail {get;set;}=new();
        public SessionTail? Backfill {get;set;}
        public DateTime Seen {get;set;}
        public bool Initialized {get;set;}
    }
    private readonly Dictionary<string,Track> tracks=new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string,(string Title,string Initial)> names=new(StringComparer.Ordinal);
    private readonly HashSet<string> projects=new(StringComparer.OrdinalIgnoreCase);
    private DateTimeOffset nextDiscovery;
    private string warning="",stateDb="",logsDb="";
    private bool discoveryComplete;
    private long lastLog;
    public string Home => home;
    public MonitorSnapshot Read()
    {
        warning="";
        try{if(DateTimeOffset.Now>=nextDiscovery){Discover();nextDiscovery=DateTimeOffset.Now.AddSeconds(10);}}
        catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException){warning=e.Message;discoveryComplete=false;}
        int quickBudget=8,backfillBudget=8*1024*1024;
        bool firstRead=tracks.Values.All(t=>!t.Initialized);
        foreach(var item in tracks.OrderByDescending(x=>x.Value.Seen).ToArray())
        {
            try
            {
                if(!item.Value.Initialized)
                {
                    if(quickBudget--<=0)continue;
                    item.Value.Tail.QuickRead(item.Key);item.Value.Initialized=true;
                    if(item.Value.Tail.PartialHistory)item.Value.Backfill=new();
                }
                else item.Value.Tail.Read(item.Key,256*1024);
                if(item.Value.Backfill!=null&&!firstRead&&backfillBudget>0)
                {
                    item.Value.Backfill.Read(item.Key,1024*1024);
                    backfillBudget-=1024*1024;
                    if(item.Value.Backfill.Offset>=new FileInfo(item.Key).Length)
                    {item.Value.Tail.Dispose();item.Value.Tail=item.Value.Backfill;item.Value.Backfill=null;}
                }
            }
            catch(Exception e) when(e is IOException or UnauthorizedAccessException){item.Value.Tail.State.Error=e.Message;}
        }
        ReadCompactions();
        var chats=tracks.Values.Select(x=>x.Tail.State).Where(x=>x.Id.Length>0)
            .GroupBy(x=>x.Id).Select(g=>
            {
                var states=g.ToArray();var s=states.OrderByDescending(x=>x.LastEvent).First();var lifecycle=states.OrderByDescending(x=>x.LifecycleAt).First();
                var total=states.OrderByDescending(x=>x.TotalAt).First();var latest=states.OrderByDescending(x=>x.UsageAt).First();
                if(s.Cwd.Length>0)projects.Add(s.Cwd);names.TryGetValue(s.Id,out var n);var view=s.View(n.Title??"",n.Initial??"");
                bool partial=tracks.Values.Any(t=>states.Contains(t.Tail.State)&&(t.Backfill!=null||t.Tail.PartialHistory));
                var activity=ActivityCollector.Combine(states.Select(x=>x.Activity));
                bool newerBoundary=s.LastCompact>latest.UsageAt||s.LifecycleAt>latest.UsageAt&&s.Window!=latest.Window;
                return view with{Active=lifecycle.Active,LifecycleKnown=lifecycle.LifecycleKnown,Total=total.Total,
                    Latest=newerBoundary?Usage.Empty:latest.Latest,UsageAt=newerBoundary?DateTimeOffset.MinValue:latest.UsageAt,
                    Activity=activity with{Partial=activity.Partial||partial},Compactions=states.Sum(x=>x.Compactions),LastCompact=states.Max(x=>x.LastCompact),Revision=states.Sum(x=>x.Revision)};
            })
            .OrderByDescending(x=>x.Active).ThenByDescending(x=>x.LastEvent).ToArray();
        var quota=tracks.Values.Select(x=>x.Tail.State.RecordedQuota).Where(x=>x!=null).OrderByDescending(x=>x!.Observed).FirstOrDefault();
        bool complete=discoveryComplete&&tracks.Count>0&&tracks.Values.All(x=>x.Initialized&&x.Backfill==null&&!x.Tail.PartialRecord&&!x.Tail.PartialHistory&&x.Tail.State.LifecycleKnown&&x.Tail.State.Error.Length==0&&x.Tail.State.Id.Length>0);
        if(warning.Length==0&&tracks.Values.Any(x=>!x.Initialized||x.Backfill!=null))warning="CTC reads earlier records.";
        return new(DateTimeOffset.Now,chats,projects.OrderBy(x=>x,StringComparer.OrdinalIgnoreCase).ToArray(),
            tracks.Values.SelectMany(x=>x.Tail.State.Events).DistinctBy(x=>(x.Id,x.At,x.Total)).ToArray(),quota,discoveryComplete,complete,warning,logsDb.Length>0?"Live log and rollout records":"Rollout records");
    }
    private static string LatestDatabase(string folder,string prefix) => Directory.Exists(folder)?
        Directory.EnumerateFiles(folder,prefix+"_*.sqlite").OrderByDescending(p=>int.TryParse(Regex.Match(Path.GetFileName(p),@"_(\d+)\.sqlite$").Groups[1].Value,out int n)?n:0).FirstOrDefault()??"":"";
    private Dictionary<string,string>[] Query(string db,string sql)
    {try{return NativeSqlite.Query(db,sql,1024);}catch(Exception e) when(e is IOException or DllNotFoundException or EntryPointNotFoundException){warning=e.Message;return [];}}
    private void Discover()
    {
        string sqliteHome=Environment.GetEnvironmentVariable("CODEX_SQLITE_HOME")??home;
        string configured=ContextSettings.String(ContextSettings.Read(Path.Combine(home,"config.toml")),"sqlite_home");if(configured.Length>0)sqliteHome=configured;
        stateDb=LatestDatabase(sqliteHome,"state");logsDb=LatestDatabase(sqliteHome,"logs");
        var candidates=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var row in Query(stateDb,"SELECT rollout_path,cwd FROM threads WHERE archived = 0 ORDER BY updated_at DESC LIMIT 1024;"))
        {if(row.GetValueOrDefault("rollout_path") is {Length:>0} p&&File.Exists(p))candidates.Add(p);if(row.GetValueOrDefault("cwd") is {Length:>0} cwd)projects.Add(cwd);}
        var rows=Query(stateDb,"SELECT id,name,title FROM threads ORDER BY updated_at DESC LIMIT 512;");
        if(rows.Length==0)rows=Query(stateDb,"SELECT id,title FROM threads ORDER BY updated_at DESC LIMIT 512;");
        var uiNames=new HashSet<string>(StringComparer.Ordinal);
        foreach(var row in rows)if(row.GetValueOrDefault("name") is {Length:>0})uiNames.Add(row.GetValueOrDefault("id")??"");
        foreach(var row in rows)names[row.GetValueOrDefault("id")??""]=(row.GetValueOrDefault("name")??row.GetValueOrDefault("title")??"",row.GetValueOrDefault("title")??"");
        foreach(var row in Query(stateDb,"SELECT DISTINCT cwd FROM threads WHERE cwd IS NOT NULL LIMIT 512;"))if(row.GetValueOrDefault("cwd") is {Length:>0} p)projects.Add(p);
        string index=Path.Combine(home,"session_index.jsonl");
        if(File.Exists(index))
        {
            using var stream=new FileStream(index,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
            if(stream.Length>2*1024*1024)stream.Seek(-2*1024*1024,SeekOrigin.End);
            using var reader=new StreamReader(stream);
            if(stream.Position>0)reader.ReadLine();
            while(reader.ReadLine() is { } line)
            {
                if(line.Length>65536)continue;
                try{using var d=JsonDocument.Parse(line);var r=d.RootElement;string id=r.Text("id"),title=r.Text("thread_name");if(title.Length==0)title=r.Text("name");if(id.Length>0&&title.Length>0&&!uiNames.Contains(id)){names.TryGetValue(id,out var old);names[id]=(title,old.Initial??"");}}
                catch(JsonException){}
            }
        }
        string saved=Path.Combine(home,".codex-global-state.json");
        if(File.Exists(saved)&&new FileInfo(saved).Length<4*1024*1024)
        {
            using var doc=JsonDocument.Parse(File.ReadAllText(saved));var r=doc.RootElement;
            foreach(var p in r.At("electron-saved-workspace-roots").Items())if(p.Text().Length>0)projects.Add(p.Text());
            var locals=r.At("local-projects");
            var values=locals.ValueKind==JsonValueKind.Object?locals.EnumerateObject().Select(p=>p.Value):locals.Items();
            foreach(var p in values)foreach(var path in p.At("rootPaths").Items())if(path.Text().Length>0)projects.Add(path.Text());
        }
        string sessions=Path.Combine(home,"sessions");
        if(Directory.Exists(sessions))
        {
            foreach(var f in Directory.EnumerateFiles(sessions,"*.jsonl",SearchOption.AllDirectories).Select(x=>new FileInfo(x)).OrderByDescending(x=>x.LastWriteTimeUtc).Take(1024))candidates.Add(f.FullName);
        }
        discoveryComplete=candidates.Count<1024; // A bounded scan cannot certify idle state beyond its coverage.
        foreach(string path in candidates.OrderByDescending(File.GetLastWriteTimeUtc).Take(1024))
        {
            if(tracks.TryGetValue(path,out var existing)){existing.Seen=DateTime.UtcNow;continue;}
            var track=new Track{Seen=File.GetLastWriteTimeUtc(path)};
            tracks[path]=track;
        }
        foreach(string path in tracks.Where(x=>!candidates.Contains(x.Key)&&!x.Value.Tail.State.Active).OrderBy(x=>x.Value.Seen).Take(Math.Max(0,tracks.Count-1024)).Select(x=>x.Key).ToArray())
        {tracks[path].Tail.Dispose();tracks[path].Backfill?.Dispose();tracks.Remove(path);}
        if(names.Count>2048)foreach(string key in names.Keys.Where(id=>!tracks.Values.Any(t=>t.Tail.State.Id==id)).Take(names.Count-2048).ToArray())names.Remove(key);
    }
    private void ReadCompactions()
    {
        if(logsDb.Length==0)return;
        if(lastLog==0)
        {
            var initial=Query(logsDb,$"SELECT coalesce(max(id),0) AS id FROM logs WHERE ts < {DateTimeOffset.Now.AddMinutes(-3).ToUnixTimeSeconds()};");
            if(initial.Length>0)long.TryParse(initial[0].GetValueOrDefault("id"),out lastLog);
        }
        foreach(var row in Query(logsDb,$"SELECT id,ts,thread_id FROM logs WHERE id > {lastLog} AND target='codex_api::sse::responses' AND feedback_log_body LIKE '%response.compaction.compacting%' UNION ALL SELECT max(id),0,NULL FROM logs ORDER BY id;"))
        {
            if(long.TryParse(row.GetValueOrDefault("id"),out long id))lastLog=Math.Max(lastLog,id);
            if(!long.TryParse(row.GetValueOrDefault("ts"),out long ts)||ts==0)continue;
            DateTimeOffset at;try{at=DateTimeOffset.FromUnixTimeSeconds(ts);}catch(ArgumentOutOfRangeException){continue;}
            foreach(var t in tracks.Values.Where(x=>x.Tail.State.Id==row.GetValueOrDefault("thread_id")))if(t.Tail.State.Active&&at>=t.Tail.State.LifecycleAt&&at>t.Tail.State.LastCompact)t.Tail.State.CompactingAt=at;
        }
    }
    public void Dispose(){foreach(var t in tracks.Values){t.Tail.Dispose();t.Backfill?.Dispose();}}
}
