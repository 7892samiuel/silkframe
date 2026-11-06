using System;using System.Diagnostics;using System.IO;using System.Text;using System.Runtime.InteropServices;using System.Security.Principal;using System.Text.RegularExpressions;using System.Web.Script.Serialization;
class ImageSkinLaunchBroker {
 [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr OpenThread(uint access,bool inherit,int tid);
 [DllImport("kernel32.dll")]static extern uint GetProcessIdOfThread(IntPtr t);
 [DllImport("kernel32.dll")]static extern uint ResumeThread(IntPtr t);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll")]static extern bool GetProcessTimes(IntPtr p,out long creation,out long exit,out long kernel,out long user);
 [DllImport("kernel32.dll")]static extern bool GetThreadTimes(IntPtr p,out long creation,out long exit,out long kernel,out long user);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern int GetPackageFullName(IntPtr p,ref uint n,StringBuilder b);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern int GetPackagePathByFullName(string name,ref uint n,StringBuilder b);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern bool QueryFullProcessImageName(IntPtr p,uint flags,StringBuilder b,ref int n);
 [DllImport("advapi32.dll")]static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
 static void Log(object value){try{File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"native-startup-events.jsonl"),new JavaScriptSerializer().Serialize(value)+Environment.NewLine);}catch{}}
 [STAThread]static int Main(string[] args){
  int pid,tid;if(args.Length!=4||args[0]!="-p"||args[2]!="-tid"||!int.TryParse(args[1],out pid)||!int.TryParse(args[3],out tid)||pid<=0||tid<=0)return 2;
  IntPtr thread=OpenThread(0x802,false,tid),process=IntPtr.Zero;bool resume=thread!=IntPtr.Zero&&GetProcessIdOfThread(thread)==(uint)pid;string error=null;bool patched=false;uint count=uint.MaxValue;int port=0;object shutdownGate=null;var clock=Stopwatch.StartNew();
  try{
   if(!resume)throw new InvalidOperationException("Initial thread ownership cannot be established");
   process=OpenProcess(0x1038,false,pid);if(process==IntPtr.Zero)throw new InvalidOperationException("Cannot open startup argument parameters");
   long born,exit,kernel,user,tborn;if(!GetProcessTimes(process,out born,out exit,out kernel,out user)||!GetThreadTimes(thread,out tborn,out exit,out kernel,out user)||DateTime.UtcNow.ToFileTimeUtc()-born>TimeSpan.FromSeconds(20).Ticks||tborn<born||tborn-born>TimeSpan.FromSeconds(2).Ticks)throw new InvalidOperationException("Not a fresh initial activation");
   using(var p=Process.GetProcessById(pid))if(p.SessionId!=Process.GetCurrentProcess().SessionId)throw new InvalidOperationException("Different user session");
   IntPtr token;if(!OpenProcessToken(process,8,out token))throw new InvalidOperationException("Cannot inspect activation owner");
   try{using(var owner=new WindowsIdentity(token))if(owner.User.Value!=WindowsIdentity.GetCurrent().User.Value)throw new InvalidOperationException("Different activation owner");}finally{CloseHandle(token);}
   uint size=0;if(GetPackageFullName(process,ref size,null)!=122||size>1024)throw new InvalidOperationException("No package identity");var name=new StringBuilder((int)size);if(GetPackageFullName(process,ref size,name)!=0||!Regex.IsMatch(name.ToString(),@"^OpenAI\.Codex_\d+\.\d+\.\d+\.\d+_x64__2p2nqsd0c76g0$"))throw new InvalidOperationException("Not the official Codex package");
   size=0;if(GetPackagePathByFullName(name.ToString(),ref size,null)!=122||size>32768)throw new InvalidOperationException("Package path is unavailable");var packageRoot=new StringBuilder((int)size);if(GetPackagePathByFullName(name.ToString(),ref size,packageRoot)!=0)throw new InvalidOperationException("Cannot resolve official installation");
   string official=Path.Combine(packageRoot.ToString(),"app","ChatGPT.exe");var actual=new StringBuilder(32768);int length=actual.Capacity;if(!QueryFullProcessImageName(process,0,actual,ref length))throw new InvalidOperationException("Cannot inspect process image");
   if(!String.Equals(actual.ToString(),official,StringComparison.OrdinalIgnoreCase))return 0; // Other package entry points resume untouched.
   if(File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"original-profile.stop")))return 0;
   var configFile=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"native-startup-config.json");if(new FileInfo(configFile).Length>16384)throw new InvalidOperationException("Oversized startup configuration");
   dynamic config=new JavaScriptSerializer().DeserializeObject(File.ReadAllText(configFile));
   if((string)config["package"]!=name.ToString()||(string)config["sid"]!=WindowsIdentity.GetCurrent().User.Value||!String.Equals((string)config["officialImage"],official,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Startup configuration does not match this package/user");
   string cmd=NativeStartupArguments.ReadCommand(process,official);
   if(Regex.IsMatch(cmd,@"(?:^|\s)--(?:type|remote-debugging[^=\s]*|user-data-dir)(?:=|\s|$)"))return 0;
   shutdownGate=NativeShutdownGate.Wait(pid,official);
   port=ImageSkinNative.FreePort();
   NativeStartupArguments.AddPort(process,official,(string)config["argumentAlias"],port);patched=true;
  }catch(Exception ex){error=ex.Message;}
  finally{
   if(resume)count=ResumeThread(thread);
   // Loading UI is prepared asynchronously after the original thread resumes.
   // This helper never launches a browser. Optional independent loading UI
   // is explicitly selected in loading-config.json.
   if(patched&&resume&&count<=1)try{
    string helper=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ImageSkinLoadingHost.exe");
    if(File.Exists(helper)&&File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"loading-config.json"))){
     long creation,ex,k,u;if(GetProcessTimes(process,out creation,out ex,out k,out u)){
      var loadingFile=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"loading-config.json");dynamic loading=new JavaScriptSerializer().DeserializeObject(File.ReadAllText(loadingFile));
      if((!loading.ContainsKey("enabled")||(bool)loading["enabled"])&&loading.ContainsKey("loadingMode")&&(string)loading["loadingMode"]=="native-overlay"){
       dynamic service=Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));service.Connect();dynamic task=service.GetFolder("\\").GetTask("CodexImageSkinLoading");
       if(task.Definition.Actions.Count!=1||!String.Equals((string)task.Definition.Actions.Item(1).Path,helper,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Loading task identity differs");
       task.Run(new string[]{pid.ToString(),port.ToString(),creation.ToString()});
      }
     }
    }
   }catch(Exception loadingError){Log(new{at=DateTime.UtcNow.ToString("o"),pid=pid,loadingDispatchError=loadingError.Message});} // App activation is already resumed.
   if(thread!=IntPtr.Zero)CloseHandle(thread);if(process!=IntPtr.Zero)CloseHandle(process);
   Log(new{at=DateTime.UtcNow.ToString("o"),pid=pid,tid=tid,preparedInPlace=patched,port=port,resumed=resume&&count<=1,previousSuspendCount=count,spawnedBrowser=false,forcedExit=false,shutdownGate=shutdownGate,error=error,elapsedMs=clock.ElapsedMilliseconds});
  }
  return resume&&count<=1?0:1;
 }
}
