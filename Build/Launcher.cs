using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
// Precompiled identity bridge avoids compiling C# on each widget startup.
public static class WidgetIdentity {
 [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
 public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
}
// Pure in-memory scanning keeps large rollout backfills off the UI path.
// The scanner does not execute JavaScript or retain source text.
public sealed class CTCActivityMask {
 public string Text; public bool Partial;
}
public static class CTCActivityScanner {
 public static CTCActivityMask Mask(string code) {
  char[] mask=code.ToCharArray(); char quote='\0'; int comment=0;
  bool escaped=false, partial=false, regexClass=false;
  for(int i=0;i<mask.Length;i++) {
   char c=code[i], next=i+1<code.Length?code[i+1]:'\0';
   if(comment==1) {mask[i]=' ';if(c=='\n')comment=0;continue;}
   if(comment==2) {mask[i]=' ';if(c=='*' && next=='/'){mask[++i]=' ';comment=0;}continue;}
   if(quote!='\0') {
    mask[i]=' ';
    if(escaped)escaped=false;
    else if(c=='\\')escaped=true;
    else if(quote=='/' && c=='[')regexClass=true;
    else if(quote=='/' && c==']')regexClass=false;
    else if(c==quote && !regexClass)quote='\0';
    continue;
   }
   if(c=='/' && (next=='/' || next=='*')) {comment=next=='/'?1:2;mask[i]=' ';mask[++i]=' ';continue;}
   if(c=='"' || c=='\'' || c=='`') {quote=c;mask[i]=' ';if(c=='`')partial=true;continue;}
   if(c=='/') {
    int j=i-1;while(j>=0 && Char.IsWhiteSpace(code[j]))j--;
    if(j<0 || "=(:,[!&|?{;".IndexOf(code[j])>=0) {quote='/';mask[i]=' ';partial=true;}
   }
  }
  if(quote!='\0' || comment==2)partial=true;
  return new CTCActivityMask {Text=new string(mask),Partial=partial};
 }
}
static class Launcher {
 [STAThread] static void Main(string[] args) {
  try {
   string root=AppDomain.CurrentDomain.BaseDirectory;
   bool setup=Path.GetFileNameWithoutExtension(Application.ExecutablePath).Equals("Setup",StringComparison.OrdinalIgnoreCase);
   string script=setup ? "Install.ps1" : (args.Length>0 && args[0]=="/watch" ? "Watch-App.ps1" : "Overlay.ps1");
   string launchMode=!setup && args.Length>0 && args[0]=="/auto" ? " -AutoLaunch" : "";
   var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"),"-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \""+Path.Combine(root,script)+"\""+launchMode);
   info.UseShellExecute=false; info.CreateNoWindow=true; info.WorkingDirectory=root;
   Process.Start(info);
  } catch(Exception e) { MessageBox.Show(e.Message,"Context-Token Codex",MessageBoxButtons.OK,MessageBoxIcon.Error); }
 }
}
