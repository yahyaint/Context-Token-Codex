// SPDX-License-Identifier: MIT
using System.Text.Json;

namespace CTC.Core;

public sealed class Preferences
{
    public int Schema {get;set;}=2;
    public bool AutoOpen {get;set;}=true;
    public bool Topmost {get;set;}=true;
    public bool Compact {get;set;}=true;
    public bool StartParked {get;set;}=true;
    public string Mode {get;set;}="Context";
    public string Target {get;set;}="Either";
    public string Corner {get;set;}="BottomRight";
    public double Opacity {get;set;}=.85;
    public double Width {get;set;}=460;
    public double Height {get;set;}=650;
    public double Left {get;set;}=100;
    public double Top {get;set;}=100;
    public static Preferences Load(string path)
    {
        if(!File.Exists(path))return new();
        Preferences? p=null;bool invalid=false;
        try{p=JsonSerializer.Deserialize<Preferences>(File.ReadAllText(path),AtomicFile.Options);}catch(JsonException){invalid=true;}
        p??=new();
        if(p.Mode is not("Context" or "Tokens")){p.Mode="Context";invalid=true;}
        if(p.Target is not("Codex" or "ChatGPT" or "Either")){p.Target="Either";invalid=true;}
        if(p.Corner is not("Free" or "TopLeft" or "TopRight" or "BottomLeft" or "BottomRight")){p.Corner="BottomRight";invalid=true;}
        if(!double.IsFinite(p.Opacity)||p.Opacity<.4||p.Opacity>1){p.Opacity=.85;invalid=true;}
        if(!double.IsFinite(p.Width)||p.Width<360||p.Width>8192){p.Width=460;invalid=true;}
        if(!double.IsFinite(p.Height)||p.Height<320||p.Height>8192){p.Height=650;invalid=true;}
        p.Height=Math.Max(520,p.Height);
        if(!double.IsFinite(p.Left)||Math.Abs(p.Left)>100000){p.Left=100;invalid=true;}
        if(!double.IsFinite(p.Top)||Math.Abs(p.Top)>100000){p.Top=100;invalid=true;}
        if(invalid)File.Copy(path,path+".invalid-"+Guid.NewGuid().ToString("N")+".bak");
        return p;
    }
}
