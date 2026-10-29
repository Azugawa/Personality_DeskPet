using System;
using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Windows.Forms;
class UpdateHelper {
 [STAThread] static void Main(string[] a) {
  string backup=null,target=null; bool swapped=false;
  try {
   if(a.Length!=4) throw new Exception("更新参数无效");
   string staged=Path.GetFullPath(a[1]);
   string dir=AppDomain.CurrentDomain.BaseDirectory;
   target=Path.Combine(dir,"DeskPet.pck"); backup=target+".backup";
   using(var sha=SHA256.Create()) using(var f=File.OpenRead(staged))
    if(BitConverter.ToString(sha.ComputeHash(f)).Replace("-","").ToLowerInvariant()!=a[2]) throw new Exception("更新校验失败");
   try { var process=Process.GetProcessById(int.Parse(a[0]));
   if(!process.WaitForExit(30000)) throw new Exception("桌宠未退出，请重试"); } catch(ArgumentException) {}
   File.Copy(staged,target+".new",true);
   File.Replace(target+".new",target,backup); swapped=true;
   Process.Start(new ProcessStartInfo(Path.Combine(dir,"DeskPet.exe"),"-- --desktop-mode") {WorkingDirectory=dir});
  } catch(Exception ex) {
   if(swapped && backup!=null && File.Exists(backup)) { try {File.Copy(backup,target,true);} catch {} }
   MessageBox.Show("更新未完成："+ex.Message,"何爪爪");
  }
 }
}
