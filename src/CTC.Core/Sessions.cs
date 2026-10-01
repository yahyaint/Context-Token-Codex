// SPDX-License-Identifier: MIT
using System.Text;
using System.Text.Json;

namespace CTC.Core;

public sealed class SessionState
{
    public string Id {get;private set;}="";
    public string Model {get;private set;}="";
    public string Cwd {get;private set;}="";
    public string Tier {get;private set;}="";
    public string Originator {get;private set;}="";
    public bool Active {get;private set;}
    public bool LifecycleKnown {get;private set;}
    public bool Subagent {get;private set;}
    public long? Window {get;private set;}
    public Usage Latest {get;private set;}=Usage.Empty;
    public Usage Total {get;private set;}=Usage.Empty;
    public DateTimeOffset UsageAt {get;private set;}
    public DateTimeOffset TotalAt {get;private set;}
    public DateTimeOffset LastEvent {get;private set;}
    public DateTimeOffset LifecycleAt {get;private set;}
    public DateTimeOffset LastCompact {get;private set;}
    public DateTimeOffset CompactingAt {get;set;}
    public int Compactions {get;private set;}
    public long Revision {get;private set;}
    public string Error {get;set;}="";
    public ActivityCollector Activity {get;}=new();
    public List<TokenEvent> Events {get;}=[];
    public QuotaSnapshot? RecordedQuota {get;private set;}
    public void Parse(string line)
    {
        if(line.Length==0)return;
        using var doc=JsonDocument.Parse(line,new JsonDocumentOptions{MaxDepth=64});
        var root=doc.RootElement;var p=root.At("payload");string type=root.Text("type");var at=root.At("timestamp").Time();
        LastEvent=at>LastEvent?at:LastEvent;Revision++;
        switch(type)
        {
            case "session_meta":
                Id=p.Text("id");Cwd=p.Text("cwd");Originator=p.Text("originator");
                Subagent=p.At("source").Has("subagent");break;
            case "turn_context":
                if(p.Text("model").Length>0)Model=p.Text("model");
                if(p.Text("cwd").Length>0)Cwd=p.Text("cwd");
                Tier=p.Text("service_tier");break;
            case "response_item":
                string kind=p.Text("type");
                if(kind is "function_call" or "custom_tool_call" or "web_search_call")Activity.Request(p,at);
                else if(kind is "function_call_output" or "custom_tool_call_output")Activity.Result(p,at);
                break;
            case "event_msg":
                switch(p.Text("type"))
                {
                    case "task_started":
                        if(at!=DateTimeOffset.MinValue&&at<LifecycleAt)break;
                        LifecycleKnown=true;Active=true;LifecycleAt=at;CompactingAt=DateTimeOffset.MinValue;
                        ChangeWindow(p.Count("model_context_window"));break;
                    case "task_complete":case "turn_aborted":case "task_aborted":
                        if(at!=DateTimeOffset.MinValue&&at<LifecycleAt)break;
                        LifecycleKnown=true;Active=false;LifecycleAt=at;CompactingAt=DateTimeOffset.MinValue;break;
                    case "user_message":
                        // Older sessions can start a turn without task_started.
                        if(at>LifecycleAt){Active=true;LifecycleKnown=true;LifecycleAt=at;}break;
                    case "token_count":
                        var info=p.At("info");ChangeWindow(info.Count("model_context_window"));
                        if(info.Has("last_token_usage")){Latest=Usage.Parse(info.At("last_token_usage"));UsageAt=at;}
                        if(info.Has("total_token_usage"))UpdateTotal(Usage.Parse(info.At("total_token_usage")),at);
                        if(p.Has("rate_limits"))RecordedQuota=QuotaProvider.ParseRecorded(p.At("rate_limits"),at);
                        break;
                    case "context_compaction_started":case "compaction_started":CompactingAt=at;break;
                }
                break;
            case "token_usage_record":
                ChangeWindow(p.Count("model_context_window"));
                if(p.Has("usage")&&at>=UsageAt){Latest=Usage.Parse(p.At("usage"));UsageAt=at;}
                if(p.Has("thread_token_usage"))UpdateTotal(Usage.Parse(p.At("thread_token_usage")),at);
                break;
            case "compacted":
                Compactions++;LastCompact=at;CompactingAt=DateTimeOffset.MinValue;Latest=Usage.Empty;UsageAt=DateTimeOffset.MinValue;break;
        }
    }
    private void ChangeWindow(long? n)
    {
        if(n is not >0 || n==Window)return;
        Window=n;Latest=Usage.Empty;UsageAt=DateTimeOffset.MinValue;
    }
    private void UpdateTotal(Usage next,DateTimeOffset at)
    {
        if(at<TotalAt)return;
        if(next.Total!=Total.Total)
        {
            long? input=next.Input-Total.Input,cache=next.Cached-Total.Cached,output=next.Output-Total.Output;
            if(input is >=0 && cache is >=0 && output is >=0 && cache<=input)
                Events.Add(new(Id,at,Model,Tier,input,cache,output,Latest.Input,next.Total));
            else Events.Add(new(Id,at,"","",null,null,null,null,next.Total));
            if(Events.Count>4096)Events.RemoveRange(0,Events.Count-4096);
        }
        Total=next;TotalAt=at;
    }
    public ChatView View(string title,string initial) => new(Id,title.Length>0?title:initial.Length>0?initial:Id,initial,Model,Cwd,Active,LifecycleKnown,Subagent,
        Error.Length>0?"Read error":DateTimeOffset.Now-LastEvent>TimeSpan.FromMinutes(10)?"No recent events":CompactingAt>LastCompact?"Compacting":Active?"Running":"Idle",Window,Latest,Total,UsageAt,LastEvent,Compactions,LastCompact,Activity.Snapshot(),Error,Originator,Revision);
}

public sealed class SessionTail:IDisposable
{
    public SessionState State {get;private set;}=new();
    public long Offset {get;private set;}
    public bool PartialRecord => pending.Length>0||oversized;
    public bool PartialHistory {get;private set;}
    private readonly MemoryStream pending=new();
    private bool oversized;
    private DateTime creation;
    private byte[] prefix=[];
    private DateTime modified;
    private const int MaxRecord=8*1024*1024;
    public void Read(string path,int budget=4*1024*1024)
    {
        var f=new FileInfo(path);
        bool reset=Offset>f.Length || creation!=default&&creation!=f.CreationTimeUtc;
        if(!reset&&prefix.Length>0&&modified!=f.LastWriteTimeUtc)
        {
            using var head=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
            byte[] current=new byte[prefix.Length];int read=head.Read(current);
            reset=read!=prefix.Length||!prefix.AsSpan().SequenceEqual(current);
        }
        if(reset){State=new();Offset=0;pending.SetLength(0);oversized=false;PartialHistory=false;prefix=[];}
        creation=f.CreationTimeUtc;modified=f.LastWriteTimeUtc;
        if(Offset==f.Length)return;
        using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete,65536,FileOptions.SequentialScan);
        if(prefix.Length<Math.Min(4096,f.Length)){prefix=new byte[Math.Min(4096,f.Length)];_=stream.Read(prefix);}
        stream.Seek(Offset,SeekOrigin.Begin);byte[] buffer=new byte[65536];int remaining=budget;
        while(remaining>0)
        {
            int count=stream.Read(buffer,0,Math.Min(buffer.Length,remaining));if(count==0)break;
            remaining-=count;Offset+=count;
            int start=0;
            for(int i=0;i<count;i++)
            {
                if(buffer[i]!=10)continue;
                Append(buffer.AsSpan(start,i-start));
                if(!oversized)
                {
                    try{State.Parse(Encoding.UTF8.GetString(pending.GetBuffer(),0,(int)pending.Length).TrimEnd('\r'));}
                    catch(JsonException){PartialHistory=true;State.Error="CTC skipped an invalid record.";}
                }
                else PartialHistory=true;
                pending.SetLength(0);if(pending.Capacity>262144)pending.Capacity=8192;
                oversized=false;start=i+1;
            }
            Append(buffer.AsSpan(start,count-start));
        }
    }
    private void Append(ReadOnlySpan<byte> data)
    {
        if(oversized)return;
        if(pending.Length+data.Length>MaxRecord){oversized=true;pending.SetLength(0);return;}
        pending.Write(data);
    }
    public void QuickRead(string path)
    {
        var f=new FileInfo(path);
        const int quickBytes=256*1024;
        if(f.Length<=quickBytes){Read(path,quickBytes);return;}
        // Metadata from the head, then complete recent records from a bounded tail.
        using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
        using(var head=new MemoryStream())
        {
            byte[] bytes=new byte[65536];int count=stream.Read(bytes);
            string text=Encoding.UTF8.GetString(bytes,0,count);
            foreach(string line in text.Split('\n').SkipLast(1).Take(8))try{State.Parse(line.TrimEnd('\r'));}catch(JsonException){}
        }
        Offset=Math.Max(0,f.Length-quickBytes);stream.Seek(Offset,SeekOrigin.Begin);
        int b;do{b=stream.ReadByte();Offset++;}while(b!=-1&&b!=10);
        creation=f.CreationTimeUtc;PartialHistory=true;Read(path,quickBytes);
    }
    public void Dispose()=>pending.Dispose();
}
