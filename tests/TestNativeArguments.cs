using System;using System.IO;using System.Text;using System.Runtime.InteropServices;using System.Diagnostics;
class TestNativeArguments {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct Startup{public int cb;public IntPtr r,d,t;public int x,y,w,h,xc,yc,fill,flags;public short show,reserved;public IntPtr rp,input,output,error;}
 [StructLayout(LayoutKind.Sequential)]struct Created{public IntPtr p,t;public int pid,tid;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateProcess(string app,StringBuilder cmd,IntPtr pa,IntPtr ta,bool inherit,int flags,IntPtr env,string dir,ref Startup start,out Created child);
 [DllImport("kernel32.dll")]static extern uint ResumeThread(IntPtr t);
 [DllImport("kernel32.dll")]static extern uint WaitForSingleObject(IntPtr p,uint ms);
 [DllImport("kernel32.dll")]static extern bool GetExitCodeProcess(IntPtr p,out uint code);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr p);
 static void Check(bool value,string text){if(!value)throw new Exception(text);Console.WriteLine("PASS "+text);}
 static void Run(string image,string alias,bool shouldFit){
  var startup=new Startup{cb=Marshal.SizeOf(typeof(Startup))};Created c;string original="\""+image+"\" --single-argument \"codex://test/a b\"";
  if(!CreateProcess(image,new StringBuilder(original),IntPtr.Zero,IntPtr.Zero,false,0x08000004,IntPtr.Zero,null,ref startup,out c))throw new Exception("Cannot create fixture "+Marshal.GetLastWin32Error());
  try{
   string updated=null;bool refused=false;try{updated=NativeStartupArguments.AddPort(c.p,image,alias,9335);}catch(InvalidOperationException ex){if(!ex.Message.Contains("insufficient capacity"))throw;refused=true;}
   if(shouldFit){Check(!refused,"In-place update fits original allocation");Check(updated.EndsWith(" --single-argument \"codex://test/a b\""),"Original protocol argument tail is preserved");Check(NativeStartupArguments.ReadCommand(c.p,image)==updated,"Argument readback matches");}
   else{Check(refused,"Insufficient original capacity fails before mutation");Check(NativeStartupArguments.ReadCommand(c.p,image)==original,"Refused update preserves original command line");}
   Check(ResumeThread(c.t)==1,"Resume original initial thread once");Check(WaitForSingleObject(c.p,5000)==0,"Original fixture exits normally");uint code;GetExitCodeProcess(c.p,out code);Check(code==42,"No loader failure (exit 42)");
   var args=File.ReadAllLines(Path.Combine(Path.GetDirectoryName(image),"echo-args.txt"));
   Check(Array.IndexOf(args,"codex://test/a b")>=0,"Original URL reaches runtime");Check((Array.IndexOf(args,"--remote-debugging-port=9335")>=0)==shouldFit,"Runtime receives expected port state");
  }finally{ResumeThread(c.t);CloseHandle(c.t);CloseHandle(c.p);}
 }
 static int Main(string[] args){try{Run(args[0],args[1],true);Run(args[0],args[0],false);return 0;}catch(Exception ex){Console.Error.WriteLine(ex);return 1;}}
}
