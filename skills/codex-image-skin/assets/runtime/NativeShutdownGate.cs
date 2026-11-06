// A bounded, read-only wait for an existing prepared browser whose windows
// have already been destroyed. Hidden/minimized native windows are retained.
using System;using System.Collections.Generic;using System.Diagnostics;using System.Runtime.InteropServices;using System.Security.Principal;using System.Text;using System.Text.RegularExpressions;using System.Threading;
public static class NativeShutdownGate {
 delegate bool EnumProc(IntPtr h,IntPtr p);
 [StructLayout(LayoutKind.Sequential)]struct Rect{public int l,t,r,b;}
 [StructLayout(LayoutKind.Sequential)]struct Point{public int x,y;}
 [StructLayout(LayoutKind.Sequential)]struct Placement{public int length,flags,show;public Point min,max;public Rect normal;}
 [DllImport("user32.dll")]static extern bool EnumWindows(EnumProc f,IntPtr p);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out int pid);
 [DllImport("user32.dll")]static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")]static extern bool GetWindowPlacement(IntPtr h,ref Placement p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("kernel32.dll")]static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr p);
 [DllImport("advapi32.dll")]static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
 static bool HasMainWindow(int pid){
  bool found=false;
  if(!EnumWindows((h,p)=>{int owner;GetWindowThreadProcessId(h,out owner);if(owner!=pid)return true;
   var cls=new StringBuilder(128);GetClassName(h,cls,cls.Capacity);if(cls.ToString()!="Chrome_WidgetWin_1")return true;
   Rect r;bool large=GetWindowRect(h,out r)&&r.r-r.l>=300&&r.b-r.t>=200;
   var placement=new Placement{length=Marshal.SizeOf(typeof(Placement))};
   if(!large&&GetWindowPlacement(h,ref placement)){r=placement.normal;large=r.r-r.l>=300&&r.b-r.t>=200;}
   if(large){found=true;return false;}return true;
  },IntPtr.Zero)&&!found)throw new InvalidOperationException("Cannot inspect existing browser windows");
  return found;
 }
 public static object Wait(int activationPid,string officialImage){
  var candidates=new List<Process>();var watch=Stopwatch.StartNew();string reason="no-windowless-root";
  try{
   int session=Process.GetCurrentProcess().SessionId;string sid=WindowsIdentity.GetCurrent().User.Value;
   foreach(var candidate in Process.GetProcessesByName("ChatGPT")){
    bool retained=false;
    try{
     if(candidate.Id==activationPid||candidate.SessionId!=session||(DateTime.UtcNow-candidate.StartTime.ToUniversalTime()).TotalSeconds<8)continue;
     IntPtr p=OpenProcess(0x1010,false,candidate.Id);if(p==IntPtr.Zero)continue;
     try{
      IntPtr token;if(!OpenProcessToken(p,8,out token))continue;
      try{using(var owner=new WindowsIdentity(token))if(owner.User.Value!=sid)continue;}finally{CloseHandle(token);}
      string cmd=NativeStartupArguments.ReadCommand(p,officialImage);
      if(!Regex.IsMatch(cmd,@"(?:^|\s)--remote-debugging-port=\d+(?:\s|$)")||Regex.IsMatch(cmd,@"(?:^|\s)--type(?:=|\s|$)"))continue;
      if(HasMainWindow(candidate.Id))continue;
      candidates.Add(candidate);retained=true;
     }finally{CloseHandle(p);}
    }catch(ArgumentException){}catch(InvalidOperationException){}finally{if(!retained)candidate.Dispose();}
   }
   int count=candidates.Count;if(count==0)return new{candidateCount=0,waitMs=watch.ElapsedMilliseconds,result=reason};
   reason="bounded-timeout";
   while(watch.ElapsedMilliseconds<7000){
    bool alive=false,window=false;
    foreach(var p in candidates){if(p.HasExited)continue;alive=true;if(HasMainWindow(p.Id)){window=true;break;}}
    if(!alive){reason="old-process-exited";break;}
    if(window){reason="existing-window-returned";break;}
    Thread.Sleep(50);
   }
   return new{candidateCount=count,waitMs=watch.ElapsedMilliseconds,result=reason};
  }finally{foreach(var p in candidates)p.Dispose();}
 }
}
