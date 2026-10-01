// SPDX-License-Identifier: MIT
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CTC.Core;

public sealed class ActivityCollector
{
    private readonly Dictionary<string,ToolCall> calls = new(StringComparer.Ordinal);
    private readonly HashSet<string> shellIds = new(StringComparer.Ordinal);
    private readonly HashSet<string> toolNames=new(StringComparer.Ordinal);
    public bool Partial {get;private set;}
    public static bool IsExec(string name) => Regex.IsMatch(name,@"(^|[._])(?:exec|exec_command|write_stdin|wait)$");
    public void Request(JsonElement p,DateTimeOffset at)
    {
        string id=p.Text("call_id");if(id.Length==0)id=p.Text("id");
        if(id.Length is 0 or >256 || calls.Count>=8192) {Partial=true;return;}
        if(calls.ContainsKey(id))return;
        string name=p.Text("name");if(name.Length==0)name=p.Text("type");
        name=Regex.Replace(name,@"[\x00-\x1f]"," ");if(name.Length>100)name=name[..100];
        if(toolNames.Count>=64&&!toolNames.Contains(name))name="Other tools";
        toolNames.Add(name);
        var call=new ToolCall{Id=id,Name=name,At=at};calls.Add(id,call);
        if(!IsExec(name))return;
        string raw=p.Text("arguments");if(raw.Length==0)raw=p.Text("input");
        if(raw.Length>65536) {Partial=true;return;}
        JsonDocument? args=null;
        try
        {
            if(raw.TrimStart().StartsWith('{')) {try{args=JsonDocument.Parse(raw);}catch(JsonException){}}
            var a=args?.RootElement??default;
            if(name.EndsWith("exec_command",StringComparison.Ordinal))call.CommandTypes.AddRange(CommandKinds(a.Text("cmd")));
            else if(name.EndsWith("write_stdin",StringComparison.Ordinal))call.CommandTypes.Add(a.Text("chars").Length>0?"Process input":"Process checks");
            else if(name.EndsWith("wait",StringComparison.Ordinal))call.CommandTypes.Add("Script checks");
            else
            {
                call.CommandTypes.Add("Scripts");
                string code=a.Text("code");if(code.Length==0)code=raw;
                var (mask,partial)=Mask(code);Partial|=partial;
                foreach(Match m in Regex.Matches(mask,@"\btools\.([A-Za-z_][A-Za-z_0-9]{0,99})\s*\("))
                {
                    var key=m.Groups[1].Value;
                    if(call.ScriptReferences.Count>=64&&!call.ScriptReferences.ContainsKey(key)){Partial=true;continue;}
                    call.ScriptReferences[key]=call.ScriptReferences.GetValueOrDefault(key)+1;
                    if(key=="exec_command")
                    {
                        string tail=code.Substring(m.Index,Math.Min(8192,code.Length-m.Index));
                        var command=Regex.Match(tail,"\\bcmd\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")");
                        if(command.Success && mask.AsSpan(m.Index+command.Index,3).SequenceEqual("cmd"))
                        {
                            try {call.CommandTypes.AddRange(CommandKinds(JsonSerializer.Deserialize<string>(command.Groups[1].Value)??""));}
                            catch(JsonException){Partial=true;}
                        }
                        else Partial=true;
                    }
                }
            }
        }finally{args?.Dispose();}
    }
    public void Result(JsonElement p,DateTimeOffset at)
    {
        if(!calls.TryGetValue(p.Text("call_id"),out var call)||call.Result!=null)return;
        JsonElement output=p.At("output");
        var blocks=output.ValueKind==JsonValueKind.Array?output.Items().Take(65).ToArray():output.At("content").Items().Take(65).ToArray();
        if(blocks.Length>64)Partial=true;
        string text=output.Text();
        if(blocks.Length>0)text=blocks[0].Text("text");
        foreach(var b in blocks.Take(64))
        {
            if(b.Text("type") is not ("text" or "input_text" or "output_text"))continue;
            string t=b.Text("text");
            if(t.Length>65536){Partial=true;continue;}
            if(!t.TrimStart().StartsWith('{'))continue;
            try
            {
                using var nested=JsonDocument.Parse(t);var n=nested.RootElement;
                string chunk=n.Text("chunk_id");double? seconds=n.At("wall_time_seconds").Number();
                if(!Regex.IsMatch(chunk,@"^[a-fA-F0-9]{6,32}$")||seconds is null or <0||shellIds.Contains(chunk))continue;
                if(shellIds.Count>=8192){Partial=true;continue;}
                long? exit=Signed(n.At("exit_code"));long? session=n.Count("session_id");
                if(!exit.HasValue&&!session.HasValue)continue;
                shellIds.Add(chunk);call.ShellResults.Add(new(exit==null?"Running":exit==0?"Success":"Error",seconds,exit,session?.ToString(CultureInfo.InvariantCulture)??""));
            }catch(JsonException){}
        }
        long? code=Signed(output.At("exit_code"));double? duration=output.At("wall_time_seconds").Number();
        if(text.Length>0)
        {
            string header=text[..Math.Min(1024,text.Length)];
            var cut=Regex.Match(header,@"(?m)^(?:Final output:|Output:)");if(cut.Success)header=header[..cut.Index];
            var exit=Regex.Match(header,@"(?m)^Process exited with code (-?\d+)\s*$");
            if(exit.Success)code=long.Parse(exit.Groups[1].Value,CultureInfo.InvariantCulture);
            else if(header.StartsWith("Script completed",StringComparison.Ordinal))code=0;
            else if(Regex.IsMatch(header,@"^Script (?:failed|error)\b"))code=1;
            var time=Regex.Match(header,@"(?m)^Wall (?:time|time_seconds):\s*([0-9]+(?:\.[0-9]+)?)\s*(?:seconds)?\s*$");
            if(time.Success)duration=double.Parse(time.Groups[1].Value,CultureInfo.InvariantCulture);
            if(text.Length<=65536&&text.TrimStart().StartsWith('{'))
            {try{using var doc=JsonDocument.Parse(text);code=Signed(doc.RootElement.At("exit_code"))??code;duration=doc.RootElement.At("wall_time_seconds").Number()??duration;}catch(JsonException){}}
        }
        if(duration is null && call.At!=DateTimeOffset.MinValue && at>=call.At)duration=(at-call.At).TotalSeconds;
        call.Result=new(code==null?"Unknown":code==0?"Success":"Error",duration is >=0?duration:null,code,"");
    }
    private static long? Signed(JsonElement e)=>e.ValueKind==JsonValueKind.Number&&e.TryGetInt64(out var n)?n:null;
    public ToolActivity Snapshot()
    {
        var tools=calls.Values.GroupBy(x=>x.Name).Select(x=>Detail(x.Key,x.Select(y=>y.Result))).OrderByDescending(x=>x.Count).ToArray();
        var exec=calls.Values.Where(x=>IsExec(x.Name)).ToArray();
        var kinds=exec.SelectMany(x=>x.CommandTypes).GroupBy(x=>x).Select(x=>new KeyValuePair<string,long>(x.Key,x.Count())).ToArray();
        var refs=exec.SelectMany(x=>x.ScriptReferences).GroupBy(x=>x.Key).Select(x=>new KeyValuePair<string,long>(x.Key,x.Sum(y=>(long)y.Value))).ToArray();
        var shells=exec.SelectMany(x=>x.ShellResults).GroupBy(x=>x.ExitCode?.ToString(CultureInfo.InvariantCulture)??"Running").Select(x=>Detail(x.Key,x)).ToArray();
        return new(calls.Count,Partial,tools,exec.GroupBy(x=>x.Name).Select(x=>Detail(x.Key,x.Select(y=>y.Result))).ToArray(),kinds,refs,shells);
    }
    public static ToolActivity Combine(IEnumerable<ActivityCollector> collectors)
    {
        var merged=new ActivityCollector();
        foreach(var collector in collectors)
        {
            merged.Partial|=collector.Partial;
            foreach(var pair in collector.calls)
            {
                if(merged.calls.Count>=8192&&!merged.calls.ContainsKey(pair.Key)){merged.Partial=true;continue;}
                if(!merged.calls.TryGetValue(pair.Key,out var old)||old.Result==null&&pair.Value.Result!=null)merged.calls[pair.Key]=pair.Value;
            }
        }
        return merged.Snapshot();
    }
    private static ActivityDetail Detail(string name,IEnumerable<ToolResult?> source)
    {
        var list=source.ToArray();
        return new(name,list.Length,list.Count(x=>x!=null),list.Count(x=>x==null),list.Count(x=>x?.Status=="Success"),list.Count(x=>x?.Status=="Error"),list.Count(x=>x is not null&&x.Status is not ("Success" or "Error")),list.Sum(x=>x?.Seconds??0));
    }
    public static (string Text,bool Partial) Mask(string code)
    {
        var chars=code.ToCharArray();char quote='\0';bool escaped=false,line=false,block=false,partial=false;
        for(int i=0;i<chars.Length;i++)
        {
            char c=code[i],next=i+1<code.Length?code[i+1]:'\0';
            if(line){chars[i]=' ';if(c=='\n')line=false;continue;}
            if(block){chars[i]=' ';if(c=='*'&&next=='/'){chars[++i]=' ';block=false;}continue;}
            if(quote!='\0'){chars[i]=' ';if(escaped)escaped=false;else if(c=='\\')escaped=true;else if(c==quote)quote='\0';continue;}
            if(c=='/'&&next is '/' or '*'){line=next=='/';block=next=='*';chars[i]=' ';chars[++i]=' ';continue;}
            if(c is '"' or '\'' or '\u0060'){quote=c;chars[i]=' ';if(c=='\u0060')partial=true;}
        }
        return (new string(chars),partial||quote!='\0'||block||Regex.IsMatch(new string(chars),@"\btools\s*\["));
    }
    public static string[] CommandKinds(string text)
    {
        if(text.Length>65536)return ["Other commands"];
        // Recognize command positions only. Do not classify words in quoted output.
        var (masked,_)=Mask(text);
        var commands=Regex.Matches(masked,@"(?:^|[;|&\r\n])\s*(?:&\s*)?([A-Za-z0-9_.-]+)").Select(x=>x.Groups[1].Value.ToLowerInvariant());
        var kinds=new HashSet<string>();
        foreach(string name in commands)
        {
            string leaf=name.EndsWith(".exe",StringComparison.Ordinal)?name[..^4]:name;
            string kind=leaf switch {
                "rg" or "grep" or "findstr"=>"Search",
                "get-content" or "cat" or "type" or "get-item" or "get-childitem" or "ls" or "dir" or "test-path" or "get-filehash"=>"Read files",
                "set-content" or "add-content" or "out-file" or "copy-item" or "move-item" or "remove-item" or "new-item" or "mkdir" or "cp" or "mv" or "rm"=>"Change files",
                "git"=>"Git",
                "pytest" or "jest" or "vitest"=>"Tests",
                "npm" or "pnpm" or "yarn" or "dotnet" or "msbuild" or "cmake" or "make"=>"Build tools",
                "node" or "pwsh" or "powershell"=>"Scripts",
                _ when leaf.StartsWith("test_",StringComparison.Ordinal) && leaf.EndsWith(".ps1",StringComparison.Ordinal)=>"Tests",
                _ when leaf.StartsWith("python",StringComparison.Ordinal)||Regex.IsMatch(leaf,@"\.(ps1|py|js)$")=>"Scripts",
                _=>"Other commands"};
            kinds.Add(kind);
        }
        if(kinds.Count==0)kinds.Add("Other commands");
        return kinds.ToArray();
    }
}
