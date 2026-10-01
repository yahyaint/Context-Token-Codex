// SPDX-License-Identifier: MIT
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CTC.Core;

public static class AtomicFile
{
    public static readonly JsonSerializerOptions Options = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    public static string Version(string path) => File.Exists(path) ? Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))) : "missing";
    public static void Write(string path, string text, bool backup = false)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var temp = path + ".ctc-" + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(temp, text, new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(temp, path, backup ? path + ".bak-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N")[..6] : null);
            else File.Move(temp, path);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public static void Json<T>(string path, T value, bool backup = false) => Write(path, JsonSerializer.Serialize(value, Options), backup);
}

public static partial class ContextSettings
{
    public const string WindowKey = "model_context_window";
    public const string CompactKey = "model_auto_compact_token_limit";
    public sealed record Statement(int Start, int Length, string Text);
    public sealed record Entry(string Key, string Value, int Start, int Length);

    public static List<Statement> Statements(string content)
    {
        var result = new List<Statement>();
        int start=0, depth=0; char quote='\0'; bool multi=false, comment=false, escaped=false;
        for(int i=0;i<content.Length;i++)
        {
            char c=content[i];
            if(comment) { if(c!='\n') continue; comment=false; }
            else if(quote!='\0')
            {
                if(escaped) { escaped=false;continue; }
                if(quote=='"' && c=='\\') { escaped=true;continue; }
                if(c==quote)
                {
                    if(!multi) {quote='\0';continue;}
                    if(i+2<content.Length && content[i+1]==quote && content[i+2]==quote)
                    {
                        i+=2;while(i+1<content.Length && content[i+1]==quote) i++;
                        quote='\0';multi=false;
                    }
                }
                else if(!multi && c=='\n') throw new InvalidDataException("The TOML string is not closed. CTC did not change settings.");
                continue;
            }
            else if(c=='#') {comment=true;continue;}
            else if(c is '"' or '\'')
            {
                quote=c;multi=i+2<content.Length && content[i+1]==quote && content[i+2]==quote;
                if(multi) i+=2;continue;
            }
            else if(c is '[' or '{') depth++;
            else if(c is ']' or '}') {if(--depth<0) throw new InvalidDataException("The TOML brackets do not match.");}
            if(c=='\n' && depth==0) {result.Add(new(start,i+1-start,content[start..(i+1)]));start=i+1;}
        }
        if(quote!='\0' || depth!=0) throw new InvalidDataException("The TOML data are incomplete. CTC did not change settings.");
        if(start<content.Length) result.Add(new(start,content.Length-start,content[start..]));
        return result;
    }
    public static List<Entry> Root(string content, bool strict = false)
    {
        var result=new List<Entry>();
        foreach(var s in Statements(content))
        {
            var text=s.Text.TrimStart();
            if(text.StartsWith('[')) break;
            if(string.IsNullOrWhiteSpace(text) || text.StartsWith('#')) continue;
            var m=Regex.Match(text,"^(?:([A-Za-z0-9_-]+)|\"([^\"\\\\]+)\"|'([^']+)')\\s*=\\s*([\\s\\S]*)$");
            if(!m.Success)
            {
                if(strict) throw new InvalidDataException("CTC cannot use this TOML key format. Edit the file through Codex.");
                continue;
            }
            var key=m.Groups[1].Success?m.Groups[1].Value:m.Groups[2].Success?m.Groups[2].Value:m.Groups[3].Value;
            result.Add(new(key,m.Groups[4].Value,s.Start,s.Length));
        }
        return result;
    }
    public static List<Entry> Read(string path) => File.Exists(path) ? Root(File.ReadAllText(path)) : [];
    public static long? Numeric(IEnumerable<Entry> entries, string key)
    {
        var found=entries.Where(x=>x.Key==key).ToArray();
        if(found.Length>1) throw new InvalidDataException($"The TOML setting occurs twice: {key}.");
        if(found.Length==0) return null;
        var m=Regex.Match(found[0].Value,@"^\+?(\d(?:_?\d)*)\s*(?:#[^\r\n]*)?\s*$");
        if(!m.Success || !long.TryParse(m.Groups[1].Value.Replace("_",""),out var n)) throw new InvalidDataException($"The setting must contain a whole number: {key}.");
        return n;
    }
    public static string String(IEnumerable<Entry> entries,string key)
    {
        var entry=entries.LastOrDefault(x=>x.Key==key);
        if(entry==null) return "";
        var m=Regex.Match(entry.Value,"^([\"'])(.*?)\\1\\s*(?:#[^\\r\\n]*)?\\s*$");
        if(!m.Success) return "";
        if(m.Groups[1].Value=="\"")
        {
            try {return JsonSerializer.Deserialize<string>("\""+m.Groups[2].Value+"\"")??"";}catch(JsonException){return "";}
        }
        return m.Groups[2].Value;
    }
    public static LimitValues ReadLimits(string path) {var r=Read(path);return new(Numeric(r,WindowKey),Numeric(r,CompactKey));}
    public static long? Parse(string input,long? window=null)
    {
        string value=input.Trim().ToLowerInvariant();
        if(value=="default") return null;
        value=Regex.Replace(value,"[,_ ]","");
        decimal n;
        if(value.EndsWith('%'))
        {
            if(!window.HasValue) throw new ArgumentException("Enter a number for the context window first. Example: 200k.");
            if(!decimal.TryParse(value[..^1],NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out n)||n<=0||n>100) throw new ArgumentException("Enter a percentage above 0 and at most 100.");
            n=decimal.Round(window.Value*n/100);
        }
        else if(value.EndsWith('k'))
        {
            if(!decimal.TryParse(value[..^1],NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out n)) throw new ArgumentException("Use 200000, 200k, or default.");
            n=decimal.Round(n*1000);
        }
        else if(Regex.IsMatch(value,@"^\d+$") && decimal.TryParse(value,NumberStyles.None,CultureInfo.InvariantCulture,out n)) {}
        else throw new ArgumentException("Use 180000, 180,000, 180k, 90%, or default.");
        if(n<1||n>long.MaxValue) throw new ArgumentException("Enter a whole number of at least 1 token. Check the number size.");
        return (long)n;
    }
    public static LimitValues Draft(string window,string compact)
    {
        var w=Parse(window);var c=Parse(compact,w);
        if(w.HasValue && c>w) throw new ArgumentException("Compact at must be at most the entered context window.");
        return new(w,c);
    }
    public static (string Window,string Compact) Scale(long? baseline,int multiplier,string window,string compact)
    {
        if(baseline is null or <1) throw new ArgumentException("No base value is available. Enter a context window first.");
        if(multiplier is <1 or >3) throw new ArgumentException("Choose x1, x2, or x3.");
        decimal scaled=(decimal)baseline.Value*multiplier;
        if(scaled>long.MaxValue) throw new ArgumentException("The multiplied window is too large.");
        long denominator=Parse(window)??baseline.Value;
        long? threshold=Parse(compact,denominator);
        if(threshold>denominator) throw new ArgumentException("Compact at must be at most the current window before scaling.");
        string c=threshold==null?"default":compact.Trim().EndsWith('%')?compact.Trim():((long)Math.Max(1,decimal.Round(threshold.Value*scaled/denominator))).ToString(CultureInfo.InvariantCulture);
        return (((long)scaled).ToString(CultureInfo.InvariantCulture),c);
    }
    public static bool Save(string path,LimitValues values,string expectedVersion)
    {
        if(values.Window is <1 || values.Compact is <1 || values.Window.HasValue && values.Compact>values.Window) throw new ArgumentException("Check the entered limits.");
        if(AtomicFile.Version(path)!=expectedVersion) throw new IOException("The settings file changed. Select Undo. Enter your changes again.");
        string? folder=Path.GetDirectoryName(Path.GetFullPath(path));
        if(Path.GetFileName(folder)==".codex" && !Directory.Exists(Path.GetDirectoryName(folder))) throw new IOException("The project folder is unavailable. Restore it before Save.");
        bool existed=File.Exists(path);
        byte[] original=existed?File.ReadAllBytes(path):[];
        if((existed?Convert.ToHexString(SHA256.HashData(original)):"missing")!=expectedVersion)throw new IOException("The settings file changed. Select Undo. Try again.");
        string content="";
        if(existed){using var reader=new StreamReader(new MemoryStream(original),Encoding.UTF8,true);content=reader.ReadToEnd();}
        var entries=Root(content,true);
        var keys=new Dictionary<string,long?>{{WindowKey,values.Window},{CompactKey,values.Compact}};
        foreach(var key in keys.Keys) if(entries.Count(x=>x.Key==key)>1) throw new InvalidDataException($"The TOML setting occurs twice: {key}.");
        if(ReadLimits(path)==values) return false;
        string changed=content;
        foreach(var entry in entries.Where(x=>keys.ContainsKey(x.Key)).OrderByDescending(x=>x.Start)) changed=changed.Remove(entry.Start,entry.Length);
        string newline=content.Contains("\r\n")?"\r\n":"\n";
        changed=string.Concat(keys.OrderBy(x=>x.Key,StringComparer.Ordinal).Where(x=>x.Value.HasValue).Select(x=>$"{x.Key} = {x.Value!.Value.ToString(CultureInfo.InvariantCulture)}{newline}"))+changed;
        _=Root(changed,true);
        Directory.CreateDirectory(folder!);
        string temp=path+".ctc-"+Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(temp,changed,new UTF8Encoding(false));
            if(existed)
            {
                using var guard=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read|FileShare.Delete);
                using var current=new MemoryStream();guard.CopyTo(current);
                if(!original.AsSpan().SequenceEqual(current.ToArray())) throw new IOException("The settings file changed. Select Undo. Try again.");
                File.Replace(temp,path,path+".bak-"+DateTime.Now.ToString("yyyyMMdd-HHmmss-fff")+"-"+Guid.NewGuid().ToString("N")[..6]);
            }
            else File.Move(temp,path);
        }
        finally {if(File.Exists(temp)) File.Delete(temp);}
        return true;
    }
    public static string[] ConfigPaths(string home,string cwd)
    {
        var paths=new List<string>();
        if(Directory.Exists(cwd))
        {
            var d=new DirectoryInfo(Path.GetFullPath(cwd));bool found=false;
            while(d!=null)
            {
                paths.Add(Path.Combine(d.FullName,".codex","config.toml"));
                string git=Path.Combine(d.FullName,".git");
                if(File.Exists(git)||File.Exists(Path.Combine(git,"HEAD"))) {found=true;break;}
                d=d.Parent;
            }
            if(!found && paths.Count>1) paths.RemoveRange(1,paths.Count-1);
        }
        paths.Add(Path.Combine(home,"config.toml"));
        return paths.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    }
}

public sealed class ModelCatalog(string home)
{
    public ModelInfo? Find(string model)
    {
        var path=Path.Combine(home,"models_cache.json");
        if(!File.Exists(path)) return null;
        try
        {
            using var doc=JsonDocument.Parse(File.ReadAllText(path));
            var m=doc.RootElement.At("models").Items().FirstOrDefault(x=>x.Text("slug")==model || x.Text("model")==model);
            if(m.ValueKind==JsonValueKind.Undefined) return null;
            return new(model,m.Count("context_window"),m.Count("max_context_window")??m.Count("context_window"),m.At("effective_context_window_percent").Number());
        }
        catch(JsonException){return null;}
    }
    public LimitBaseline Baseline(string path,ChatView? chat)
    {
        var saved=ContextSettings.ReadLimits(path);var paths=ContextSettings.ConfigPaths(home,Path.GetDirectoryName(Path.GetDirectoryName(path))??"");
        string model=chat?.Model??ContextSettings.String(ContextSettings.Read(path),"model");
        if(string.IsNullOrEmpty(model)) foreach(var p in paths) {model=ContextSettings.String(ContextSettings.Read(p),"model");if(model.Length>0)break;}
        var catalog=Find(model);long? basis=saved.Window;string source="saved window";
        if(basis==null) foreach(var p in paths.Where(x=>!string.Equals(x,path,StringComparison.OrdinalIgnoreCase)))
        {basis=ContextSettings.ReadLimits(p).Window;source=string.Equals(p,Path.Combine(home,"config.toml"),StringComparison.OrdinalIgnoreCase)?"global fallback":"parent project fallback";if(basis!=null)break;}
        if(basis==null && catalog?.Window>0) {basis=catalog.Window;source="local model catalog";}
        if(basis==null && chat?.Window>0) {basis=chat.Window;source="live usable window";}
        return new(saved,basis,source,model,catalog,chat?.Window,AtomicFile.Version(path));
    }
}
