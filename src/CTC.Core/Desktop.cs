// SPDX-License-Identifier: MIT
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace CTC.Core;

public sealed record DesktopProcess(int Id,string Path);
public static class DesktopIdentity
{
    public static bool IsCodex(string path) => Regex.IsMatch(path,@"\\OpenAI\.Codex_[^\\]+\\app\\[^\\]+\.exe$|\\(?:OpenAI[.\\])?Codex\\(?:app\\)?(?:Codex|ChatGPT)\.exe$",RegexOptions.IgnoreCase);
    public static bool IsChatGPT(string path) => !IsCodex(path)&&Regex.IsMatch(path,@"\\(?:OpenAI\.ChatGPT_[^\\]+\\app\\[^\\]+|ChatGPT\\(?:app\\)?ChatGPT)\.exe$",RegexOptions.IgnoreCase);
    public static DesktopProcess[] Find(string target="Either",bool visibleOnly=false)
    {
        var result=new List<DesktopProcess>();
        foreach(var p in Process.GetProcesses())
        using(p)
        {
            try
            {
                string path=p.MainModule?.FileName??"";
                if(((target!="ChatGPT"&&IsCodex(path))||(target!="Codex"&&IsChatGPT(path)))&&(!visibleOnly||VisibleWindows(p.Id)>0))result.Add(new(p.Id,path));
            }
            catch(System.ComponentModel.Win32Exception){}catch(InvalidOperationException){}catch(NotSupportedException){}
        }
        return result.ToArray();
    }
    private delegate bool WindowCallback(nint hwnd,nint state);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback,nint state);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint hwnd,out uint processId);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint hwnd);
    [DllImport("user32.dll")] private static extern nint GetWindow(nint hwnd,uint command);
    [DllImport("user32.dll")] private static extern bool PostMessage(nint hwnd,uint message,nint w,nint l);
    public static int VisibleWindows(int processId)
    {
        int count=0;EnumWindows((h,_)=>{GetWindowThreadProcessId(h,out uint id);if(id==processId&&IsWindowVisible(h)&&GetWindow(h,4)==0)count++;return true;},0);return count;
    }
    public static bool CloseNormally(DesktopProcess process)
    {
        try
        {
            using var p=Process.GetProcessById(process.Id);
            if(!string.Equals(p.MainModule?.FileName,process.Path,StringComparison.OrdinalIgnoreCase))return false;
            bool sent=false;
            EnumWindows((h,_)=>{GetWindowThreadProcessId(h,out uint id);if(id==process.Id&&IsWindowVisible(h)&&GetWindow(h,4)==0){GetWindowThreadProcessId(h,out uint current);if(current==process.Id)sent|=PostMessage(h,0x10,0,0);}return true;},0);
            return sent;
        }
        catch(System.ComponentModel.Win32Exception){return false;}catch(ArgumentException){return false;}catch(InvalidOperationException){return false;}
    }
}

public static class NativeSqlite
{
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_open_v2(byte[] file,out nint db,int flags,nint vfs);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_close(nint db);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_busy_timeout(nint db,int ms);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_prepare_v2(nint db,byte[] sql,int bytes,out nint statement,nint tail);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_step(nint statement);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_finalize(nint statement);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern int sqlite3_column_count(nint statement);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern nint sqlite3_column_name(nint statement,int column);
    [DllImport("winsqlite3.dll",CallingConvention=CallingConvention.Cdecl)] private static extern nint sqlite3_column_text(nint statement,int column);
    public static Dictionary<string,string>[] Query(string path,string sql,int limit=512)
    {
        if(!File.Exists(path))return [];
        nint db=0,statement=0;
        try
        {
            if(sqlite3_open_v2(Encoding.UTF8.GetBytes(path+"\0"),out db,1,0)!=0)throw new IOException("CTC cannot read the Codex database.");
            sqlite3_busy_timeout(db,100);
            if(sqlite3_prepare_v2(db,Encoding.UTF8.GetBytes(sql+"\0"),-1,out statement,0)!=0)throw new IOException("The Codex database format changed.");
            var rows=new List<Dictionary<string,string>>();
            int status=101;
            while(rows.Count<limit&&(status=sqlite3_step(statement))==100)
            {
                var row=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                for(int i=0;i<sqlite3_column_count(statement);i++)row[Marshal.PtrToStringUTF8(sqlite3_column_name(statement,i))??""]=Marshal.PtrToStringUTF8(sqlite3_column_text(statement,i))??"";
                rows.Add(row);
            }
            if(status is not(100 or 101))throw new IOException("The Codex database is busy or unavailable. CTC will retry.");
            return rows.ToArray();
        }
        finally{if(statement!=0)sqlite3_finalize(statement);if(db!=0)sqlite3_close(db);}
    }
}
