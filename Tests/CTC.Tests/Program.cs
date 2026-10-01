// SPDX-License-Identifier: MIT
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using CTC.Core;

if(args.Contains("--rpc-fixture"))
{
    using var reader=new StreamReader(Console.OpenStandardInput(),new UTF8Encoding(false),false);
    string? init=await reader.ReadLineAsync();
    if(init==null||init.StartsWith('\uFEFF'))return 9;
    using var d=JsonDocument.Parse(init);if(d.RootElement.Text("method")!="initialize")return 8;
    Console.WriteLine("{\"id\":1,\"result\":{}}");
    _=await reader.ReadLineAsync();_=await reader.ReadLineAsync();
    if(args.Contains("--hang")){await Task.Delay(30000);return 7;}
    if(args.Contains("--invalid-params")){Console.WriteLine("{\"id\":2,\"error\":{\"code\":-32602}}");_=await reader.ReadLineAsync();}
    if(args.Contains("--noisy"))Console.Error.WriteLine(new string('x',131072));
    int authIndex=Array.IndexOf(args,"--change-auth");
    if(authIndex>=0)File.WriteAllText(args[authIndex+1],"changed fixture sign-in");
    Console.WriteLine(args.Contains("--invalid-params")?"{\"id\":3,\"result\":{\"rateLimits\":{\"planType\":\"free\",\"secondary\":{\"usedPercent\":42,\"windowDurationMins\":10080,\"resetsAt\":1900000000}}}}":"{\"id\":2,\"result\":{\"rateLimits\":{\"planType\":\"free\",\"secondary\":{\"usedPercent\":42,\"windowDurationMins\":10080,\"resetsAt\":1900000000}}}}");
    return 0;
}
var root=Path.Combine(Path.GetTempPath(),"ctc-native-"+Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
int count=0;
void Check(bool condition,string name){if(!condition)throw new Exception(name);count++;Console.WriteLine("PASS "+name);}
void Reject(Action action,string name){bool rejected=false;try{action();}catch(Exception e) when(e is ArgumentException or IOException or InvalidDataException or JsonException){rejected=true;}Check(rejected,name);}
JsonElement Element(object value)=>JsonSerializer.SerializeToElement(value);
string Record(string type,object payload,DateTimeOffset? time=null)=>JsonSerializer.Serialize(new{type,timestamp=(time??DateTimeOffset.UtcNow).ToString("o"),payload});
ChatView Chat(SessionState state)=>state.View("Chat","Initial");
try
{
    foreach(var culture in new[]{"en-US","de-DE","ar-EG"})
    {
        CultureInfo.CurrentCulture=CultureInfo.GetCultureInfo(culture);
        Check(ContextSettings.Draft("200k","90%")==new LimitValues(200000,180000),"Percentage "+culture);
        Check(ContextSettings.Parse("180,000")==180000&&ContextSettings.Parse("180_000")==180000,"Separators "+culture);
        var scaled=ContextSettings.Scale(200000,2,"200k","180k");scaled=ContextSettings.Scale(200000,3,scaled.Window,scaled.Compact);
        Check(scaled.Window=="600000"&&scaled.Compact=="540000","Anchored scalers "+culture);
    }
    CultureInfo.CurrentCulture=CultureInfo.InvariantCulture;
    Reject(()=>ContextSettings.Draft("default","90%"),"Unknown denominator");
    Reject(()=>ContextSettings.Draft("200k","201k"),"Compaction exceeds window");
    foreach(var bad in new[]{"0","-1","NaN","9223372036854775808","1e6","101%"})Reject(()=>ContextSettings.Parse(bad,200000),"Reject "+bad);
    Reject(()=>ContextSettings.Scale(long.MaxValue,3,"200k","default"),"Scaler overflow");
    string folder=Path.Combine(root,"space & Unicode العربية");Directory.CreateDirectory(folder);
    string config=Path.Combine(folder,".codex","config.toml");Directory.CreateDirectory(Path.GetDirectoryName(config)!);
    string original="# Keep\nmodel = 'fixture-model'\ntext = \"\"\"\nmodel_context_window = 111\n\"\"\"\narray = [\n1, 2\n]\n[table]\nmodel_context_window = 22\n";
    File.WriteAllText(config,original);string version=AtomicFile.Version(config);
    Check(ContextSettings.Save(config,new(200000,180000),version),"Save settings");
    Check(File.ReadAllText(config).Contains(original)&&ContextSettings.ReadLimits(config)==new LimitValues(200000,180000),"Preserve TOML tables strings");
    Check(Directory.GetFiles(Path.GetDirectoryName(config)!,"*.bak-*").Length==1,"Settings backup");
    Reject(()=>ContextSettings.Save(config,new(300000,270000),version),"Stale save blocked");
    version=AtomicFile.Version(config);ContextSettings.Save(config,new(null,null),version);
    Check(File.ReadAllText(config)==original,"Default removes overrides only");
    File.WriteAllText(config,"model_context_window = 1\nmodel_context_window = 2\n");
    Reject(()=>ContextSettings.Save(config,new(200000,180000),AtomicFile.Version(config)),"Duplicate key blocked");
    File.WriteAllText(config,"model_context_window = 200_000 # inline\n");
    Check(ContextSettings.ReadLimits(config).Window==200000,"TOML numeric separators");
    File.WriteAllText(Path.Combine(root,"models_cache.json"),"{\"models\":[{\"slug\":\"fixture-model\",\"context_window\":200000,\"max_context_window\":600000}]}");
    Check(new ModelCatalog(root).Find("fixture-model")?.UsablePercent==null,"Unknown usable percentage");
    File.WriteAllText(Path.Combine(root,"config.toml"),"model = 'fixture-model'\nmodel_context_window = 250000\n");
    Check(new ModelCatalog(root).Baseline(config,null).Base==200000,"Saved base");
    ContextSettings.Save(config,new(null,null),AtomicFile.Version(config));
    Check(new ModelCatalog(root).Baseline(config,null).Base==250000,"Global base");
    var queue=new QueueStore(Path.Combine(root,"limits-queue.json"),root);queue.Save(config,new(200000,180000));queue.Save(config,new(300000,270000));
    Check(queue.Read().Length==1&&queue.Read()[0].Window==300000,"Queue replace scope");
    Check(queue.Views([])[0].Changed,"Queue external edit");
    string queuePath=Path.Combine(root,"bad-queue.json");File.WriteAllText(queuePath,"{\"Version\":2,\"Entries\":[]}");
    Reject(()=>new QueueStore(queuePath,root).Save(config,new(1,1)),"Future queue preserved");
    Check(File.ReadAllText(queuePath).Contains("\"Version\":2"),"Future queue unchanged");
    var usage=new Usage(100,80,30,10);Check(usage.Total==130&&usage.Uncached==20&&usage.OtherOutput==20,"Token subset accounting");
    Check(new Usage(10,20,5,10).Uncached==null&&new Usage(long.MaxValue,0,1,0).Total==null,"Usage corruption overflow");
    var now=DateTimeOffset.UtcNow;var state=new SessionState();
    state.Parse(Record("session_meta",new{id="chat",cwd=folder,originator="Codex Desktop"}));
    state.Parse(Record("turn_context",new{model="fixture-model",service_tier="standard"}));
    state.Parse(Record("event_msg",new{type="task_started",model_context_window=190000}));
    state.Parse(Record("event_msg",new{type="token_count",info=new{model_context_window=190000,last_token_usage=new{input_tokens=100,cached_input_tokens=80,output_tokens=30,reasoning_output_tokens=10},total_token_usage=new{input_tokens=100,cached_input_tokens=80,output_tokens=30,reasoning_output_tokens=10}}}));
    Check(Chat(state).Active&&Chat(state).Latest.Input==100&&Chat(state).Total.Total==130,"Lifecycle and tokens");
    state.Parse(Record("compacted",new{}));state.Parse(Record("event_msg",new{type="task_complete"}));
    Check(!state.Active&&state.Compactions==1&&state.Latest.Input==null,"Idle and compaction clears numerator");
    state.Parse(Record("event_msg",new{type="task_started",model_context_window=380000}));
    Check(state.Latest.Input==null&&state.Window==380000,"New window clears old numerator");
    string tailPath=Path.Combine(root,"tail.jsonl");string text=Record("session_meta",new{id="utf8",cwd="العربية"});
    byte[] all=Encoding.UTF8.GetBytes(text+"\n");
    File.WriteAllBytes(tailPath,all[..(all.Length-2)]);using var tail=new SessionTail();tail.Read(tailPath);
    Check(tail.PartialRecord&&tail.State.Id=="","Partial line withheld");
    using(var f=new FileStream(tailPath,FileMode.Append))f.Write(all.AsSpan(all.Length-2));tail.Read(tailPath);
    Check(tail.State.Id=="utf8"&&!tail.PartialRecord,"UTF8 split record");
    File.WriteAllText(tailPath,Record("session_meta",new{id="new"})+"\n");tail.Read(tailPath);
    Check(tail.State.Id=="new","Truncated rollout reset");
    var activity=new ActivityCollector();
    activity.Request(Element(new{type="function_call",call_id="one",name="exec_command",arguments="{\"cmd\":\"Get-Content private; rg private\"}"}),now);
    activity.Request(Element(new{type="function_call",call_id="one",name="exec_command"}),now);
    activity.Result(Element(new{call_id="one",output="Process exited with code 1\nWall time: 1.5 seconds\nOutput:\nProcess exited with code 0"}),now.AddSeconds(2));
    activity.Request(Element(new{type="custom_tool_call",call_id="two",name="functions.exec",input="/* tools.fake() */ await tools.exec_command({cmd:\"rg private\"}); const x=\"tools.no()\"; tools.apply_patch(\"private\")"}),now);
    activity.Result(Element(new{call_id="two",output=new[]{new{type="input_text",text="Script completed"},new{type="input_text",text="{\"chunk_id\":\"abcdef12\",\"exit_code\":2,\"wall_time_seconds\":1.2,\"output\":\"private\"}"}}}),now.AddSeconds(3));
    var a=activity.Snapshot();
    Check(a.Calls==2&&a.Exec.Sum(x=>x.Failure)==1&&a.Exec.Sum(x=>x.Success)==1,"Activity call results");
    Check(a.References.Length==2&&a.ShellResults.Single().Failure==1,"Nested script shell details");
    Check(!JsonSerializer.Serialize(a).Contains("private")&&!JsonSerializer.Serialize(a).Contains("fake"),"No command or output retained");
    activity.Result(Element(new{call_id="two",output="duplicate"}),now);Check(activity.Snapshot().Calls==2,"Output deduplication");
    Check(ActivityCollector.Mask("tools[name](); tools.a(); const x=\u0060tools.b()\u0060").Partial,"Dynamic script partial");
    Check(ActivityCollector.CommandKinds("echo \"git private\"").SequenceEqual(new[]{"Other commands"}),"Quoted words excluded");
    var copy=new ActivityCollector();copy.Request(Element(new{call_id="one",name="exec_command"}),now);
    Check(ActivityCollector.Combine([activity,copy]).Calls==2,"Resumed call deduplication");
    state.Parse(Record("future_event",new{new_schema="value"}));Check(state.Id=="chat","Future record tolerated");
    string corrupt=Path.Combine(root,"corrupt.jsonl");File.WriteAllText(corrupt,"{invalid}\n"+Record("session_meta",new{id="recovered"})+"\n");
    using(var badTail=new SessionTail()){badTail.Read(corrupt);Check(badTail.PartialHistory&&badTail.State.Id=="recovered","Corrupt record does not stop tail");}
    var quota=QuotaProvider.Parse(Element(new{accountId="private-account",rateLimitsByLimitId=new{weekly=new{planType="free",secondary=new{usedPercent=42,windowDurationMins=10080,resetsAt=now.AddDays(2).ToUnixTimeSeconds()}}}}),"Fixture",now);
    Check(quota.Windows.Length==1&&quota.Windows[0].Label=="7d"&&quota.Plan=="free","Weekly-only quota");
    Check(!quota.AccountKey.Contains("private"),"Account identifier hashed");
    var estimator=new QuotaEstimator();
    estimator.Update(quota,[],Path.Combine(AppContext.BaseDirectory,"Quota.Rates.json"),now);
    Check(estimator.Share("chat",now).Contains("--"),"First quota sample unknown share");
    string rates=Path.Combine(root,"rates.json");File.WriteAllText(rates,JsonSerializer.Serialize(new{ @checked=now.ToString("o"),models=new Dictionary<string,double[]>{{"fixture-model",[10,1,20]}}}));
    var baselineQuota=quota with{Observed=now,Windows=[quota.Windows[0] with{Used=10}]};
    var estimate=new QuotaEstimator();estimate.Update(baselineQuota,[],rates,now);
    var eventOne=new TokenEvent("a",now.AddSeconds(1),"fixture-model","standard",100,50,10,100,110);
    var eventTwo=eventOne with{Id="b",Input=200,Cached=100,Output=20};
    estimate.Update(baselineQuota with{Observed=now.AddSeconds(2),Windows=[baselineQuota.Windows[0] with{Used=16}]},[eventOne,eventTwo],rates,now.AddSeconds(2));
    var estimated=estimate.Windows.Values.Single();Check(Math.Abs(estimated.Shares["a"]-2)<.0001&&Math.Abs(estimated.Shares["b"]-4)<.0001,"Weighted quota intervals");
    estimate.Update(baselineQuota with{Observed=now.AddSeconds(4),Windows=[baselineQuota.Windows[0] with{Used=18}]},[eventOne with{At=now.AddSeconds(3),Model="unknown"}],rates,now.AddSeconds(4));
    Check(Math.Abs(estimated.Unattributed-2)<.0001,"Unknown model quota stays unattributed");
    Check(Math.Abs(estimated.Shares.Values.Sum()+estimated.Unattributed-8)<.0001,"Quota allocation conservation");
    estimate.Update(baselineQuota with{Observed=now.AddSeconds(5),Windows=[baselineQuota.Windows[0] with{Used=3}]},[],rates,now.AddSeconds(5));
    Check(estimate.Windows.Values.Single().Shares.Count==0,"Quota decrease resets baseline");
    Check(QuotaEstimator.Weight(eventOne with{Tier="priority"},JsonDocument.Parse(File.ReadAllText(rates)).RootElement,now)==null,"Unsupported tier weight unknown");
    var snapshot=new MonitorSnapshot(now,[Chat(state)],[],[],null,true,true,"","Fixture");
    Check(!RestartGate.Ready(snapshot),"Busy restart blocked");state.Parse(Record("event_msg",new{type="task_complete"}));
    snapshot=snapshot with{Chats=[Chat(state)]};Check(RestartGate.Ready(snapshot),"Idle restart gate");
    Check(!RestartGate.Ready(snapshot with{LifecycleComplete=false}),"Unknown restart blocked");
    string restartPath=Path.Combine(root,"restart.json");var restart=new RestartController(restartPath);restart.Request();var expiry=restart.Read()!.ExpiresAt;restart.Request();restart.Cancel();
    Check(restart.Read()!.ExpiresAt==expiry&&restart.Read()!.Status=="Cancelled","Restart expiry retained");
    string preferences=Path.Combine(root,"overlay.json");File.WriteAllText(preferences,"{\"Opacity\":99,\"Mode\":\"Tokens\",\"StartParked\":true}");
    var prefs=Preferences.Load(preferences);Check(prefs.Opacity==.85&&prefs.Mode=="Tokens"&&Directory.GetFiles(root,"*.invalid-*.bak").Length==1,"Preference migration backup");
    Check(DesktopIdentity.IsCodex(@"C:\Program Files\WindowsApps\OpenAI.Codex_2\app\ChatGPT.exe")&&!DesktopIdentity.IsCodex(@"C:\OpenAI.Codex_2\app\resources\codex.exe"),"Update-proof app identity");
    var provider=new QuotaProvider(root,root);
    string dotnet=Environment.ProcessPath!;
    string[] rpcArgs=Path.GetFileNameWithoutExtension(dotnet).Equals("dotnet",StringComparison.OrdinalIgnoreCase)?[typeof(Program).Assembly.Location,"--rpc-fixture"]:["--rpc-fixture"];
    var rpc=await provider.ReadAsync(executable:dotnet,arguments:rpcArgs,timeout:TimeSpan.FromSeconds(8));
    Check(rpc.Windows.Length==1&&rpc.Windows[0].Used==42,"Live RPC UTF8 no BOM");
    var retry=await provider.ReadAsync(executable:dotnet,arguments:rpcArgs.Concat(["--invalid-params","--noisy"]),timeout:TimeSpan.FromSeconds(8));
    Check(retry.Windows.Length==1,"RPC older schema retry and stderr drain");
    bool timedOut=false;var timeoutWatch=Stopwatch.StartNew();
    try{await provider.ReadAsync(executable:dotnet,arguments:rpcArgs.Append("--hang"),timeout:TimeSpan.FromMilliseconds(200));}catch(TimeoutException){timedOut=true;}
    Check(timedOut&&timeoutWatch.Elapsed<TimeSpan.FromSeconds(4),"RPC timeout closes owned helper");
    bool changedSignIn=false;
    try{await provider.ReadAsync(executable:dotnet,arguments:rpcArgs.Concat(["--change-auth",Path.Combine(root,"auth.json")]),timeout:TimeSpan.FromSeconds(8));}catch(IOException){changedSignIn=true;}
    Check(changedSignIn,"In-flight sign-in result rejected");
    File.WriteAllText(Path.Combine(root,"auth.json"),"fixture");Check(QuotaProvider.ProfileStamp(root)!=rpc.ProfileStamp,"Sign-in metadata changes stamp");
    string sessions=Path.Combine(root,"sessions");Directory.CreateDirectory(sessions);
    File.WriteAllText(Path.Combine(sessions,"fixture.jsonl"),Record("session_meta",new{id="fixture",cwd=folder})+"\n"+Record("event_msg",new{type="task_complete"})+"\n");
    File.WriteAllText(Path.Combine(root,"session_index.jsonl"),"{\"id\":\"fixture\",\"thread_name\":\"Renamed chat\"}\n");
    File.WriteAllText(Path.Combine(root,".codex-global-state.json"),JsonSerializer.Serialize(new Dictionary<string,object>{{"local-projects",new{idle=new{rootPaths=new[]{folder}}}}}));
    using(var monitor=new MonitorService(root))
    {
        var view=monitor.Read();Check(view.Chats.Single().Title=="Renamed chat"&&view.Projects.Contains(folder),"Monitor UI names and idle projects");
        Check(view.LifecycleComplete,"Monitor safe lifecycle coverage");
    }
    string database=Path.Combine(root,"state_100.sqlite");
    static string Sql(string text)=>"'"+text.Replace("'","''")+"'";
    FixtureDatabase.Create(database,"CREATE TABLE threads(id TEXT,name TEXT,title TEXT,cwd TEXT,archived INTEGER,updated_at INTEGER,rollout_path TEXT);"+
        "INSERT INTO threads VALUES('fixture','UI name','Initial title',"+Sql(folder)+",0,1,"+Sql(Path.Combine(sessions,"fixture.jsonl"))+");");
    var dbStamp=File.GetLastWriteTimeUtc(database);
    Check(NativeSqlite.Query(database,"SELECT name FROM threads;").Single()["name"]=="UI name","Native SQLite read");
    Check(File.GetLastWriteTimeUtc(database)==dbStamp,"Native SQLite does not write source");
    using(var monitor=new MonitorService(root))Check(monitor.Read().Chats.Single().Title=="UI name","Desktop name wins over initial index");
    Console.WriteLine($"PASS {count} native checks");return 0;
}
finally{Directory.Delete(root,true);}

internal static class FixtureDatabase
{
    [System.Runtime.InteropServices.DllImport("winsqlite3.dll",CallingConvention=System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern int sqlite3_open_v2(byte[] path,out nint db,int flags,nint vfs);
    [System.Runtime.InteropServices.DllImport("winsqlite3.dll",CallingConvention=System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern int sqlite3_exec(nint db,byte[] sql,nint callback,nint state,nint error);
    [System.Runtime.InteropServices.DllImport("winsqlite3.dll",CallingConvention=System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern int sqlite3_close(nint db);
    public static void Create(string path,string sql)
    {
        nint db=0;
        try{if(sqlite3_open_v2(Encoding.UTF8.GetBytes(path+"\0"),out db,6,0)!=0||sqlite3_exec(db,Encoding.UTF8.GetBytes(sql+"\0"),0,0,0)!=0)throw new IOException("SQLite fixture creation failed.");}
        finally{if(db!=0)sqlite3_close(db);}
    }
}
