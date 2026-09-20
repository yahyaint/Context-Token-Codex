using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
static class Launcher {
 [STAThread] static void Main(string[] args) {
  try {
   string root=AppDomain.CurrentDomain.BaseDirectory;
   bool setup=Path.GetFileNameWithoutExtension(Application.ExecutablePath).Equals("Setup",StringComparison.OrdinalIgnoreCase);
   string script=setup ? "Install.ps1" : (args.Length>0 && args[0]=="/watch" ? "Watch-App.ps1" : "Overlay.ps1");
   var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"),"-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \""+Path.Combine(root,script)+"\"");
   info.UseShellExecute=false; info.CreateNoWindow=true; info.WorkingDirectory=root;
   Process.Start(info);
  } catch(Exception e) { MessageBox.Show(e.Message,"Context-Token Codex",MessageBoxButtons.OK,MessageBoxIcon.Error); }
 }
}
