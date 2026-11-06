// Hidden, in-process native cover checks. Does not show or operate user windows.
using System;using System.Collections.Generic;using System.Diagnostics;using System.Drawing;using System.Drawing.Imaging;using System.IO;using System.Reflection;using System.Runtime.InteropServices;using System.Web.Script.Serialization;using System.Windows.Forms;
class TestNativeCover {
 static readonly BindingFlags hidden=BindingFlags.Instance|BindingFlags.NonPublic;static List<string> checks=new List<string>();
 static void Require(bool pass,string name){if(!pass)throw new Exception(name);checks.Add(name);}
 static FieldInfo Field(Type type,string name){return type.GetField(name,hidden);}
 static Form NewForm(Type type,string folder,Dictionary<string,object> config){Directory.CreateDirectory(folder);return(Form)Activator.CreateInstance(type,BindingFlags.Instance|BindingFlags.Public,null,new object[]{Process.GetCurrentProcess(),folder,config},null);}
 [STAThread]static int Main(){string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar),outRoot=Path.Combine(root,"startup-investigation","native-cover-tests");Directory.CreateDirectory(outRoot);try{
  Application.EnableVisualStyles();var json=new JavaScriptSerializer();var config=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,"loading-config.json")));config["capturePreview"]=false;var type=typeof(ImageSkinLoadingCover).GetNestedType("CoverForm",BindingFlags.NonPublic);
  foreach(var size in new[]{new Size(1280,800),new Size(390,780)})using(var f=NewForm(type,Path.Combine(outRoot,"render-"+size.Width),config)){
   f.ClientSize=size;Field(type,"scale").SetValue(f,1f);using(var image=new Bitmap(size.Width,size.Height)){f.DrawToBitmap(image,new Rectangle(Point.Empty,size));image.Save(Path.Combine(outRoot,"render-"+size.Width+".png"),ImageFormat.Png);}
   Require(!f.Visible&&!f.ShowInTaskbar,"render "+size.Width+" remains hidden and absent from taskbar");
   var skip=(RectangleF)Field(type,"skip").GetValue(f);Require(skip.Left>=0&&skip.Top>=0&&skip.Right<=size.Width&&skip.Bottom<=size.Height,"skip control fits "+size.Width+"px viewport");
   var bitmap=(Bitmap)Field(type,"background").GetValue(f);var data=bitmap.LockBits(new Rectangle(Point.Empty,bitmap.Size),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);bool opaque=true,key=false;try{var bytes=new byte[Math.Abs(data.Stride)*bitmap.Height];Marshal.Copy(data.Scan0,bytes,0,bytes.Length);for(int i=0;i<bytes.Length;i+=4){opaque&=bytes[i+3]==255;key|=bytes[i]==255&&bytes[i+1]==0&&bytes[i+2]==255;}}finally{bitmap.UnlockBits(data);}Require(opaque&&!key,"all rendered pixels are opaque and avoid the color key at "+size.Width+"px");
   type.GetMethod("OnMouseUp",hidden).Invoke(f,new object[]{new MouseEventArgs(MouseButtons.Left,1,(int)(skip.Left+skip.Width/2),(int)(skip.Top+skip.Height/2),0)});Require((bool)Field(type,"finished").GetValue(f),"skip closes native cover at "+size.Width+"px");
  }
  string validation=Path.Combine(outRoot,"identity");using(var f=NewForm(type,validation,config)){
   var identity=new{pid=Process.GetCurrentProcess().Id,browserId="fixture-browser"};File.WriteAllText(Path.Combine(validation,"identity.json"),json.Serialize(identity));var ready=type.GetMethod("Ready",hidden);
   File.WriteAllText(Path.Combine(validation,"ready.json"),json.Serialize(new{ready=true,pid=Process.GetCurrentProcess().Id+100000,browserId="fixture-browser",themeId=config["themeId"]}));Require(!(bool)ready.Invoke(f,null),"different process readiness is rejected");
   File.WriteAllText(Path.Combine(validation,"ready.json"),json.Serialize(new{ready=true,pid=Process.GetCurrentProcess().Id,browserId="other-browser",themeId=config["themeId"]}));Require(!(bool)ready.Invoke(f,null),"stale browser readiness is rejected");
   File.WriteAllText(Path.Combine(validation,"ready.json"),json.Serialize(new{ready=true,pid=Process.GetCurrentProcess().Id,browserId="fixture-browser",themeId=config["themeId"]}));Require((bool)ready.Invoke(f,null),"matching process, browser and theme readiness is accepted");
  }
  string timeout=Path.Combine(outRoot,"timeout");using(var f=NewForm(type,timeout,config)){
   var watch=(Stopwatch)Field(type,"clock").GetValue(f);watch.Stop();var elapsed=typeof(Stopwatch).GetField("elapsed",hidden);if(elapsed==null)throw new Exception("Fixture stopwatch layout differs");elapsed.SetValue(watch,21L*Stopwatch.Frequency);Field(type,"shownAt").SetValue(f,0d);type.GetMethod("Tick",hidden).Invoke(f,null);Require((bool)Field(type,"finished").GetValue(f),"native cover times out without a readiness marker");Require(File.ReadAllText(Path.Combine(timeout,"cover.jsonl")).Contains("timeout"),"timeout closure is recorded");
  }
  string output=json.Serialize(new{pass=true,checks=checks});File.WriteAllText(Path.Combine(outRoot,"proof.json"),output);Console.WriteLine(output);return 0;
 }catch(Exception e){Console.Error.WriteLine(e);return 1;}}
}
