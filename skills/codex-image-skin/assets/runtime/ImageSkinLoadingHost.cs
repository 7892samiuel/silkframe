using System;using System.Collections.Generic;using System.Diagnostics;using System.IO;using System.Net;using System.Runtime.InteropServices;using System.Security.Cryptography;using System.Security.Principal;using System.Text;using System.Threading;using System.Web.Script.Serialization;
class ImageSkinLoadingHost {
 [DllImport("iphlpapi.dll")]static extern uint GetExtendedTcpTable(IntPtr table,ref int size,bool order,int family,int kind,uint reserved);
 [DllImport("advapi32.dll")]static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern int GetCurrentPackageFullName(ref uint size,StringBuilder name);
 static readonly JavaScriptSerializer json=new JavaScriptSerializer();static string root=AppDomain.CurrentDomain.BaseDirectory;
 static void Log(string state,string detail){try{File.AppendAllText(Path.Combine(root,"loading-host-events.jsonl"),json.Serialize(new{utc=DateTime.UtcNow.ToString("o"),state=state,detail=detail})+Environment.NewLine);}catch{}}
 static Dictionary<string,object> Read(string file){if(new FileInfo(file).Length>16384)throw new Exception("Oversized loading configuration");return json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file));}
 static bool OwnsPort(int pid,int port){int size=0;GetExtendedTcpTable(IntPtr.Zero,ref size,false,2,3,0);if(size<4||size>1048576)return false;IntPtr table=Marshal.AllocHGlobal(size);try{if(GetExtendedTcpTable(table,ref size,false,2,3,0)!=0)return false;int count=Marshal.ReadInt32(table);if(count<0||4+count*24>size)return false;bool found=false;for(int i=0;i<count;i++){IntPtr row=IntPtr.Add(table,4+i*24);int raw=Marshal.ReadInt32(row,8),p=((raw&255)<<8)|((raw>>8)&255);if(p!=port)continue;if(Marshal.ReadInt32(row,20)!=pid||Marshal.ReadInt32(row,4)!=0x0100007f)return false;found=true;}return found;}finally{Marshal.FreeHGlobal(table);}}
 static string Quote(string s){if(s.Contains("\""))throw new Exception("Invalid loading path");return "\""+s+"\"";}
 [STAThread]static int Main(string[] args){int pid,port;long born;if(args.Length!=3||!int.TryParse(args[0],out pid)||!int.TryParse(args[1],out port)||!long.TryParse(args[2],out born)||pid<=0||port<1024||port>65535)return 2;
  try{uint packageSize=0;int packageResult=GetCurrentPackageFullName(ref packageSize,null);string package="none";if(packageResult==122&&packageSize<2048){var name=new StringBuilder((int)packageSize);if(GetCurrentPackageFullName(ref packageSize,name)==0)package=name.ToString();}Log("desktop-context","helper="+Process.GetCurrentProcess().Id+" package="+package);
   using(var mutex=new Mutex(false,"Local\\CodexImageSkinLoading-"+pid+"-"+born)){
   if(!mutex.WaitOne(0))return 0;
   try{
    var configPath=Path.Combine(root,"loading-config.json");var config=Read(configPath);var native=Read(Path.Combine(root,"native-startup-config.json"));
    string sid=WindowsIdentity.GetCurrent().User.Value,official=(string)native["officialImage"];
    if((config.ContainsKey("enabled")&&!(bool)config["enabled"])||(string)native["sid"]!=sid||File.Exists(Path.Combine(root,"original-profile.stop"))||File.Exists((string)config["pausePath"]))return 0;
    using(var app=Process.GetProcessById(pid)){
     if(app.SessionId!=Process.GetCurrentProcess().SessionId||Math.Abs(app.StartTime.ToUniversalTime().ToFileTimeUtc()-born)>10000||!String.Equals(app.MainModule.FileName,official,StringComparison.OrdinalIgnoreCase))throw new Exception("Loading process identity differs");
     IntPtr handle=ImageSkinNative.OpenProcess(0x1010,false,pid);if(handle==IntPtr.Zero)throw new Exception("Cannot inspect loading browser");
     try{IntPtr token;if(!OpenProcessToken(handle,8,out token))throw new Exception("Cannot inspect loading owner");try{using(var owner=new WindowsIdentity(token))if(owner.User.Value!=sid)throw new Exception("Loading owner differs");}finally{ImageSkinNative.CloseHandle(token);}string cmd=NativeStartupArguments.ReadCommand(handle,official);if(cmd.Contains("--type=")||!cmd.Contains("--remote-debugging-port="+port))throw new Exception("Loading browser command differs");}finally{ImageSkinNative.CloseHandle(handle);}
     string folder=Path.Combine(root,"loading-sessions",pid+"-"+born);Directory.CreateDirectory(folder);
     bool overlayMode=config.ContainsKey("loadingMode")&&(string)config["loadingMode"]=="native-overlay";
     using(var cover=overlayMode?new ImageSkinLoadingCover(app,folder,config):null)
     {
     string browserId=null,url=null;var clock=Stopwatch.StartNew();
     while(clock.ElapsedMilliseconds<14000&&!app.HasExited){
      if(OwnsPort(pid,port))try{var request=(HttpWebRequest)WebRequest.Create("http://127.0.0.1:"+port+"/json/version");request.Proxy=null;request.AllowAutoRedirect=false;request.Timeout=250;request.ReadWriteTimeout=250;using(var response=request.GetResponse())using(var reader=new StreamReader(response.GetResponseStream())){var version=json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());url=(string)version["webSocketDebuggerUrl"];var u=new Uri(url);if(u.Scheme!="ws"||u.Host!="127.0.0.1"||u.Port!=port||u.Query.Length!=0||!u.AbsolutePath.StartsWith("/devtools/browser/"))throw new Exception("Loading endpoint differs");browserId=u.AbsolutePath.Substring("/devtools/browser/".Length);if(browserId.Length<1||browserId.Length>200||!OwnsPort(pid,port))throw new Exception("Loading ownership changed");break;}}catch{browserId=null;}
      Thread.Sleep(40);
     }
     if(browserId==null)return 0;
     string node=(string)config["nodePath"];using(var stream=File.OpenRead(node))using(var hash=SHA256.Create()){if(!String.Equals(BitConverter.ToString(hash.ComputeHash(stream)).Replace("-",""),(string)config["nodeSha256"],StringComparison.OrdinalIgnoreCase))throw new Exception("Loading Node integrity differs");}
     string identity=Path.Combine(folder,"identity.json");File.WriteAllText(identity,json.Serialize(new{pid=pid,port=port,browserId=browserId,webSocketDebuggerUrl=url,officialImage=official}),new UTF8Encoding(false));
     var start=new ProcessStartInfo{FileName=node,Arguments=Quote(Path.Combine(root,"ImageSkinReadyMonitor.cjs"))+" "+Quote(identity)+" "+Quote(configPath),WorkingDirectory=root,UseShellExecute=false,CreateNoWindow=true};
     using(var child=Process.Start(start)){Log("started","Browser "+pid+"; loadingMode="+(overlayMode?"native-overlay":"page"));child.WaitForExit(45000);}
     }
    }
   }finally{mutex.ReleaseMutex();}
  }return 0;}catch(Exception e){Log("skipped",e.Message);return 1;}
 }
}
