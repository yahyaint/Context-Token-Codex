// SPDX-License-Identifier: MIT
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CTC.Core;

public sealed class QuotaProvider(string home,string dataDirectory)
{
    public static string ProfileStamp(string home)
    {
        var f=new FileInfo(Path.Combine(home,"auth.json"));
        string metadata=Path.GetFullPath(home)+"|"+(f.Exists?f.LastWriteTimeUtc.Ticks:0)+"|"+(f.Exists?f.Length:0);
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(metadata)));
    }
    public static QuotaSnapshot Parse(JsonElement response,string source,DateTimeOffset observed,string stamp="")
    {
        string account=response.Text("accountId");
        string key=account.Length==0?"":Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(account)));
        var buckets=new List<(string Id,JsonElement Data)>();
        var map=response.At("rateLimitsByLimitId");
        if(map.ValueKind==JsonValueKind.Object) foreach(var p in map.EnumerateObject())buckets.Add((p.Name,p.Value));
        if(buckets.Count==0&&response.Has("rateLimits"))buckets.Add(("codex",response.At("rateLimits")));
        var windows=new List<QuotaWindow>();string plan="";
        foreach(var b in buckets)
        {
            string id=b.Data.Text("limitId");if(id.Length==0)id=b.Id;
            if(b.Data.Text("planType").Length>0)plan=b.Data.Text("planType");
            foreach(string role in new[]{"primary","secondary"})
            {
                var w=b.Data.At(role);double? used=w.At("usedPercent").Number();long? mins=w.Count("windowDurationMins");
                if(used==null||mins is null or <=0 or >int.MaxValue)continue;
                DateTimeOffset? reset=null;long? epoch=w.Count("resetsAt");
                if(epoch!=null){try{reset=DateTimeOffset.FromUnixTimeSeconds(epoch.Value);}catch(ArgumentOutOfRangeException){}}
                windows.Add(new(id,role,(int)mins.Value,Math.Clamp(used.Value,0,100),reset));
            }
        }
        return new(key,stamp,plan,source,observed,windows.ToArray());
    }
    public static QuotaSnapshot ParseRecorded(JsonElement e,DateTimeOffset at)
    {
        var roles=new Dictionary<string,object?> {["planType"]=e.Text("plan_type"),["limitId"]=e.Text("limit_id")};
        foreach(string role in new[]{"primary","secondary"})
        {
            var r=e.At(role);if(r.ValueKind==JsonValueKind.Undefined)continue;
            roles[role]=new{usedPercent=r.At("used_percent").Number(),windowDurationMins=r.Count("window_minutes"),resetsAt=r.Count("resets_at")};
        }
        using var d=JsonDocument.Parse(JsonSerializer.Serialize(new{rateLimits=roles}));
        return Parse(d.RootElement,"Recorded local quota",at);
    }
    public static string FindExecutable()
    {
        foreach(string dir in (Environment.GetEnvironmentVariable("PATH")??"").Split(Path.PathSeparator))
        {try{string p=Path.Combine(dir,"codex.exe");if(File.Exists(p))return p;}catch(ArgumentException){}}
        string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"OpenAI","Codex","bin");
        if(Directory.Exists(root))
        {var p=Directory.EnumerateFiles(root,"codex.exe",SearchOption.AllDirectories).OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();if(p!=null)return p;}
        foreach(var proc in Process.GetProcesses())
        {
            using(proc)
            {try{string p=proc.MainModule?.FileName??"";if(!DesktopIdentity.IsCodex(p))continue;string dir=Path.GetDirectoryName(p)!;
                foreach(string candidate in new[]{Path.Combine(dir,"resources","codex.exe"),Path.Combine(dir,"codex.exe")})if(File.Exists(candidate)&&!DesktopIdentity.IsCodex(candidate))return candidate;
            }catch(System.ComponentModel.Win32Exception){}catch(InvalidOperationException){}}
        }
        string apps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"WindowsApps");
        try
        {
            foreach(string package in Directory.EnumerateDirectories(apps,"OpenAI.Codex_*").OrderByDescending(x=>x,StringComparer.Ordinal))
            {
                foreach(string candidate in new[]{Path.Combine(package,"app","resources","codex.exe"),Path.Combine(package,"app","resources","bin","codex.exe")})
                    if(File.Exists(candidate))return candidate;
            }
        }catch(UnauthorizedAccessException){}catch(DirectoryNotFoundException){}
        throw new FileNotFoundException("CTC cannot find the Codex CLI. Install Codex. Sign in to Codex.");
    }
    public async Task<QuotaSnapshot> ReadAsync(CancellationToken cancellation=default,string? executable=null,IEnumerable<string>? arguments=null,TimeSpan? timeout=null)
    {
        string stamp=ProfileStamp(home);
        var info=new ProcessStartInfo(executable??FindExecutable())
        {UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,
            StandardInputEncoding=new UTF8Encoding(false),StandardOutputEncoding=new UTF8Encoding(false),StandardErrorEncoding=new UTF8Encoding(false)};
        info.Environment["CODEX_HOME"]=home;
        if(arguments!=null) foreach(string a in arguments)info.ArgumentList.Add(a);
        else
        {
            string scope=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(home))))[..16];
            string state=Path.Combine(dataDirectory,"UsageState",scope);Directory.CreateDirectory(state);
            info.Environment["CODEX_SQLITE_HOME"]=state;info.WorkingDirectory=state;
            info.ArgumentList.Add("-c");info.ArgumentList.Add("sqlite_home="+JsonSerializer.Serialize(state.Replace('\\','/')));info.ArgumentList.Add("app-server");
        }
        using var process=new Process{StartInfo=info};
        using var deadline=CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(timeout??TimeSpan.FromSeconds(45));
        bool started=false;
        try
        {
            process.Start();started=true;
            var drain=DrainAsync(process.StandardError,deadline.Token);
            await process.StandardInput.WriteLineAsync("{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"context-token-codex\",\"version\":\"7.0.0\"}}}");
            await process.StandardInput.FlushAsync(deadline.Token);
            int lines=0;
            while(lines++<4096)
            {
                string? line=await process.StandardOutput.ReadLineAsync(deadline.Token);
                if(line==null)throw new IOException("The Codex CLI closed before it sent account quota data.");
                if(line.Length>1024*1024)continue;
                JsonDocument d;try{d=JsonDocument.Parse(line);}catch(JsonException){continue;}
                using(d)
                {
                    var m=d.RootElement;long? id=m.Count("id");
                    if(id==1)
                    {
                        if(m.Has("error"))throw new IOException("Codex CLI initialization failed. Update Codex or sign in.");
                        await process.StandardInput.WriteLineAsync("{\"method\":\"initialized\",\"params\":{}}");
                        await process.StandardInput.WriteLineAsync("{\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{\"excludeResetCreditDetails\":true}}");
                        await process.StandardInput.FlushAsync(deadline.Token);
                    }
                    if(id==2 && m.At("error").At("code").ValueKind==JsonValueKind.Number && m.At("error").At("code").GetInt32()==-32602)
                    {
                        await process.StandardInput.WriteLineAsync("{\"id\":3,\"method\":\"account/rateLimits/read\",\"params\":{}}");
                        await process.StandardInput.FlushAsync(deadline.Token);continue;
                    }
                    if(id is 2 or 3)
                    {
                        if(m.Has("error"))throw new IOException("Account quota data are unavailable. Check Codex sign-in and network connection.");
                        if(stamp!=ProfileStamp(home))throw new IOException("The Codex sign-in changed. Refresh account quotas.");
                        return Parse(m.At("result"),"Codex CLI",DateTimeOffset.Now,stamp);
                    }
                }
            }
            throw new IOException("The CLI sent too many diagnostic records. Update Codex.");
        }
        catch(OperationCanceledException) when(!cancellation.IsCancellationRequested)
        {throw new TimeoutException("The account quota request timed out. CTC keeps the last verified reading.");}
        finally
        {
            deadline.Cancel();
            if(started)
            {
                try{process.StandardInput.Close();}catch(IOException){}
                try{if(!process.HasExited&&!process.WaitForExit(1000)){process.Kill(true);process.WaitForExit(1500);}}catch(InvalidOperationException){}
            }
        }
    }
    private static async Task DrainAsync(StreamReader reader,CancellationToken token)
    {try{while(await reader.ReadLineAsync(token)!=null){}}catch(OperationCanceledException){}catch(IOException){}catch(ObjectDisposedException){}}
}

public sealed class QuotaEstimator
{
    public sealed class WindowState
    {
        public DateTimeOffset Reset {get;set;}
        public int Minutes {get;set;}
        public DateTimeOffset Start {get;set;}
        public DateTimeOffset LastAt {get;set;}
        public DateTimeOffset HighAt {get;set;}
        public double HighUsed {get;set;}
        public double LastUsed {get;set;}
        public Dictionary<string,double> Shares {get;set;}=new();
        public double Unattributed {get;set;}
        public int Spans {get;set;}
        public int Mixed {get;set;}
    }
    public int Schema {get;set;}=1;
    public string Scope {get;set;}="";
    public Dictionary<string,WindowState> Windows {get;set;}=new();
    public string Warning {get;set;}="";
    public void Update(QuotaSnapshot quota,IEnumerable<TokenEvent> events,string ratesPath,DateTimeOffset now)
    {
        JsonDocument? rates=null;try{if(File.Exists(ratesPath))rates=JsonDocument.Parse(File.ReadAllText(ratesPath));}catch(JsonException){}
        using(rates)
        {
            foreach(var q in quota.Windows)
            {
                if(q.Reset is null || q.Reset<=now || now-quota.Observed>TimeSpan.FromMinutes(2)||quota.Observed>now.AddMinutes(1))continue;
                if(!Windows.TryGetValue(q.Key,out var w)||w.Reset!=q.Reset||quota.Observed>w.LastAt&&q.Used<w.LastUsed)
                {Windows[q.Key]=new(){Reset=q.Reset.Value,Minutes=q.Minutes,Start=quota.Observed,LastAt=quota.Observed,HighAt=quota.Observed,HighUsed=q.Used,LastUsed=q.Used};continue;}
                if(quota.Observed<=w.LastAt)continue;
                w.LastAt=quota.Observed;w.LastUsed=q.Used;double delta=q.Used-w.HighUsed;if(delta<=0)continue;
                var weights=new Dictionary<string,double>();bool unknown=false;
                foreach(var e in events.Where(x=>x.At>w.HighAt&&x.At<=quota.Observed).DistinctBy(x=>(x.Id,x.At,x.Total)))
                {
                    double? weight=Weight(e,rates?.RootElement??default,now);
                    if(weight==null){unknown=true;continue;}
                    weights[e.Id]=weights.GetValueOrDefault(e.Id)+weight.Value;
                }
                double total=weights.Values.Sum();
                if(unknown||total<=0||quota.Observed-w.HighAt>TimeSpan.FromMinutes(10)||w.Shares.Count>512)w.Unattributed+=delta;
                else
                {foreach(var p in weights)w.Shares[p.Key]=w.Shares.GetValueOrDefault(p.Key)+delta*p.Value/total;w.Spans++;if(weights.Count>1)w.Mixed++;}
                w.HighUsed=q.Used;w.HighAt=quota.Observed;
            }
            foreach(string key in Windows.Where(x=>x.Value.Reset<=now).Select(x=>x.Key).ToArray())Windows.Remove(key);
        }
    }
    public static double? Weight(TokenEvent e,JsonElement rates,DateTimeOffset now)
    {
        var checkedAt=rates.At("checked").Time();
        if(checkedAt==DateTimeOffset.MinValue||now-checkedAt>TimeSpan.FromDays(90))return null;
        var r=rates.At("models").At(e.Model).Items().Select(x=>x.Number()).ToArray();
        if(r.Length!=3||r.Any(x=>x==null)||e.Tier is not ("" or "default" or "auto" or "standard")||
            e.Input is null or <0||e.Cached is null or <0||e.Output is null or <0||e.Cached>e.Input||e.RequestInput>272000)return null;
        return ((e.Input-e.Cached)*r[0]+e.Cached*r[1]+e.Output*r[2])/1_000_000;
    }
    public string Share(string chat,DateTimeOffset now)
    {
        var parts=new List<string>();
        foreach(var group in Windows.Values.Where(x=>x.Reset>now).GroupBy(x=>x.Minutes))
        {
            var w=group.ToArray();string label=group.Key==300?"5h":group.Key==10080?"7d":$"{group.Key}m";
            parts.Add(w.Length==1&&now-w[0].LastAt<=TimeSpan.FromMinutes(2)&&w[0].Shares.TryGetValue(chat,out var n)?$"{label} {(n<1?"<1%":$"~{n:0}%")}":label+" --");
        }
        return parts.Count>0?string.Join(" | ",parts):"--";
    }
    public static QuotaEstimator Load(string path,string scope)
    {
        try{if(File.Exists(path)&&new FileInfo(path).Length<2*1024*1024){var e=JsonSerializer.Deserialize<QuotaEstimator>(File.ReadAllText(path),AtomicFile.Options);if(e?.Schema==1&&e.Scope==scope)return e;}}catch(JsonException){}catch(IOException){}
        return new(){Scope=scope};
    }
}
