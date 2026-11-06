// Own-process native fixture only. Does not activate or operate other apps.
using System;using System.Collections.Generic;using System.Diagnostics;using System.Drawing;using System.Drawing.Imaging;using System.IO;using System.Reflection;using System.Runtime.InteropServices;using System.Threading;using System.Web.Script.Serialization;using System.Windows.Forms;
class TestNativeHandover {
 delegate IntPtr Proc(IntPtr h,uint m,IntPtr w,IntPtr l);
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct WC {public uint style;public Proc proc;public int cls,window;public IntPtr instance,icon,cursor,brush;public string menu,name;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern ushort RegisterClass(ref WC c);
 [DllImport("user32.dll")]static extern IntPtr DefWindowProc(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern IntPtr GetModuleHandle(string name);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr param);
 [DllImport("user32.dll")]static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
 [DllImport("user32.dll")]static extern bool DestroyWindow(IntPtr h);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]static extern IntPtr GetWindow(IntPtr h,uint command);
 [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")]static extern IntPtr GetWindowLongPtr(IntPtr h,int index);
 [DllImport("user32.dll")]static extern bool UpdateWindow(IntPtr h);
 [DllImport("gdi32.dll")]static extern bool BitBlt(IntPtr destination,int x,int y,int width,int height,IntPtr source,int sx,int sy,uint flags);
 static Proc callback=DefWindowProc;static List<string> checks=new List<string>();static string folder;
 static void Check(bool okay,string name){if(!okay)throw new Exception(name);checks.Add(name);}
 static void Pump(int ms){var until=DateTime.UtcNow.AddMilliseconds(ms);while(DateTime.UtcNow<until){Application.DoEvents();Thread.Sleep(10);}}
 static Dictionary<string,object> Find(string name){string f=Path.Combine(folder,"cover.jsonl");if(!File.Exists(f))return null;foreach(string line in File.ReadAllLines(f))try{var row=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(line);if((string)row["eventName"]==name)return (Dictionary<string,object>)row["data"];}catch{}return null;}
 static bool Wait(Func<bool> condition,int ms){var until=DateTime.UtcNow.AddMilliseconds(ms);while(DateTime.UtcNow<until){if(condition())return true;Pump(20);}return condition();}
 static IntPtr Window(string name){IntPtr h=CreateWindowEx(0,"Chrome_WidgetWin_1",name,0x00CF0000,300,200,800,600,IntPtr.Zero,IntPtr.Zero,GetModuleHandle(null),IntPtr.Zero);if(h==IntPtr.Zero)throw new Exception("Fixture native window creation failed");return h;}
 static bool Above(IntPtr upper,IntPtr lower){for(int i=0;i<500;i++){lower=GetWindow(lower,3);if(lower==upper)return true;if(lower==IntPtr.Zero)return false;}return false;}
 static void ValidatePinnedReplacement(ImageSkinLoadingCover cover,IntPtr a,IntPtr h){
  var flags=BindingFlags.Instance|BindingFlags.NonPublic;var form=(Form)typeof(ImageSkinLoadingCover).GetField("form",flags).GetValue(cover);Exception failure=null;
  form.Invoke(new Action(()=>{IntPtr replacement=IntPtr.Zero;object surface=null;MethodInfo restack=null;try{
   surface=form.GetType().GetField("surface",flags).GetValue(form);restack=surface.GetType().GetMethod("Restack");restack.Invoke(surface,new object[]{a,true});
   Check((GetWindowLongPtr(h,-20).ToInt64()&8)!=0,"foreground startup cover is temporarily pinned");
   replacement=Window("Skin pin race test B");SetWindowPos(replacement,IntPtr.Zero,300,200,802,602,0x50);
   // The UI thread is still inside this callback: no timer tick has had an
   // opportunity to repair the order after B appears.
   Check(Above(h,replacement),"replacement shown at top cannot overtake the cover before any repair tick");
   restack.Invoke(surface,new object[]{replacement,false});Check((GetWindowLongPtr(h,-20).ToInt64()&8)==0,"switching away releases temporary topmost status");
  }catch(Exception e){failure=e;}finally{if(replacement!=IntPtr.Zero)DestroyWindow(replacement);if(restack!=null)restack.Invoke(surface,new object[]{a,false});}}));if(failure!=null)throw failure;
 }
 static void ValidateAnimation(ImageSkinLoadingCover cover,IntPtr handle){
  var flags=BindingFlags.Instance|BindingFlags.NonPublic;var form=(Form)typeof(ImageSkinLoadingCover).GetField("form",flags).GetValue(cover);Exception failure=null;
  form.Invoke(new Action(()=>{try{
   Type type=form.GetType();var watch=(Stopwatch)type.GetField("clock",flags).GetValue(form);var elapsed=typeof(Stopwatch).GetField("elapsed",flags);watch.Stop();long original=(long)elapsed.GetValue(watch);
   try{
    object surface=type.GetField("surface",flags).GetValue(form);Type native=surface.GetType();var area=Rectangle.Ceiling((RectangleF)type.GetField("progress",flags).GetValue(form));bool compared=true;int frames=0;
    foreach(int ms in new[]{250,550,950,1350,1750,2150}){
     elapsed.SetValue(watch,(long)(ms*(double)Stopwatch.Frequency/1000));native.GetMethod("Repaint").Invoke(surface,new object[]{area});UpdateWindow(handle);
     var frame=(BufferedGraphics)native.GetField("frame",flags).GetValue(surface);if(frame==null)throw new Exception("Native buffered frame missing");
     using(var actual=new Bitmap(form.ClientSize.Width,form.ClientSize.Height,PixelFormat.Format32bppRgb))using(var expected=new Bitmap(actual.Width,actual.Height,PixelFormat.Format32bppRgb)){
      using(var g=Graphics.FromImage(actual)){IntPtr target=g.GetHdc(),source=frame.Graphics.GetHdc();try{if(!BitBlt(target,0,0,actual.Width,actual.Height,source,0,0,0x00CC0020))throw new Exception("Buffered frame readback failed");}finally{frame.Graphics.ReleaseHdc(source);g.ReleaseHdc(target);}}
      using(var g=Graphics.FromImage(expected))type.GetMethod("PaintCover",flags).Invoke(form,new object[]{g});
      for(int y=0;y<actual.Height;y++)for(int x=0;x<actual.Width;x++)if(actual.GetPixel(x,y).ToArgb()!=expected.GetPixel(x,y).ToArgb())compared=false;
      frames++;
     }
    }
    Check(compared&&frames==6,"six native animation frames match complete rendering across a cycle; no erased bar or stale pixels");
   }finally{elapsed.SetValue(watch,original);watch.Start();}
  }catch(Exception e){failure=e;}}));if(failure!=null)throw failure;
 }
 [STAThread]static int Main(){IntPtr a=IntPtr.Zero,b=IntPtr.Zero;try{
  string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);folder=Path.Combine(root,"startup-investigation","native-handover-"+DateTime.Now.ToString("yyyyMMdd-HHmmss"));Directory.CreateDirectory(folder);var json=new JavaScriptSerializer();var config=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,"loading-config.json")));config["capturePreview"]=false;
  var wc=new WC{proc=callback,instance=GetModuleHandle(null),name="Chrome_WidgetWin_1"};if(RegisterClass(ref wc)==0)throw new Exception("Fixture class registration failed");
  a=Window("Skin loading test A");SetWindowPos(a,new IntPtr(1),300,200,800,600,0x50);
  using(var cover=new ImageSkinLoadingCover(Process.GetCurrentProcess(),folder,config)){
   Check(Wait(()=>Find("cover-shown")!=null,2500),"cover appears without taking foreground focus");IntPtr h=new IntPtr(Convert.ToInt64(Find("cover-shown")["hwnd"]));
   Check(Wait(()=>GetWindow(a,3)==h,1000),"cover is directly above A in normal z-order");
   using(var imageFile=File.Open((string)config["artPath"],FileMode.Open,FileAccess.Read,FileShare.None))Check(imageFile.Length>0,"loading cover does not lock the selected theme image");
   ValidateAnimation(cover,h);
   ValidatePinnedReplacement(cover,a,h);
   DestroyWindow(a);a=IntPtr.Zero;Pump(180);Check(IsWindowVisible(h),"cover survives A destruction and 180 ms gap");
   b=Window("Skin loading test B");SetWindowPos(b,new IntPtr(1),300,200,802,602,0x50);
   Check(Wait(()=>GetWindow(b,3)==h,1500),"same cover moves directly above replacement B");Check(IsWindowVisible(h),"cover remains visible after B replacement");
   File.WriteAllText(Path.Combine(folder,"identity.json"),json.Serialize(new{browserId="fixture-browser"}));File.WriteAllText(Path.Combine(folder,"ready.json"),json.Serialize(new{ready=true,pid=Process.GetCurrentProcess().Id,browserId="fixture-browser",themeId=config["themeId"]}));
   Check(Wait(()=>Find("cover-closed")!=null,2500),"cover automatically closes after matching theme readiness");Check((string)Find("cover-closed")["reason"]=="theme-ready","readiness is the recorded close reason");Check(IsWindowVisible(b),"B remains open after the cover closes");
  }
  var proof=json.Serialize(new{pass=true,checks=checks,folder=folder});File.WriteAllText(Path.Combine(root,"startup-investigation","native-handover-proof.json"),proof);Console.WriteLine(proof);return 0;
 }catch(Exception e){Console.Error.WriteLine(e);return 1;}finally{if(a!=IntPtr.Zero)DestroyWindow(a);if(b!=IntPtr.Zero)DestroyWindow(b);}}
}
