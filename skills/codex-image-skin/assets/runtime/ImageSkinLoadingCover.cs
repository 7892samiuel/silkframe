using System;using System.Collections.Generic;using System.Diagnostics;using System.Drawing;using System.Drawing.Drawing2D;using System.Drawing.Imaging;using System.Drawing.Text;using System.IO;using System.Runtime.InteropServices;using System.Text;using System.Threading;using System.Web.Script.Serialization;using System.Windows.Forms;
// A third, independently owned startup cover. Never owns/closes the Codex
// windows; never changes their style, visibility, geometry, focus, or lifetime.
sealed class ImageSkinLoadingCover:IDisposable {
 readonly Thread thread;readonly ManualResetEvent initialized=new ManualResetEvent(false);CoverForm form;
 public ImageSkinLoadingCover(Process browser,string folder,Dictionary<string,object> config){thread=new Thread(()=>{try{Application.EnableVisualStyles();form=new CoverForm(browser,folder,config);var context=new ApplicationContext();form.FormClosed+=(s,e)=>context.ExitThread();form.Prepare();initialized.Set();Application.Run(context);}catch(Exception e){try{File.AppendAllText(Path.Combine(folder,"cover-error.log"),e.ToString());}catch{}initialized.Set();}}){IsBackground=true,Name="Codex skin loading cover"};thread.SetApartmentState(ApartmentState.STA);thread.Start();initialized.WaitOne(300);}
 public void Dispose(){try{if(form!=null&&!form.IsDisposed&&form.IsHandleCreated)form.BeginInvoke(new Action(()=>form.Finish("helper-ended",false)));}catch{}thread.Join(1800);initialized.Dispose();}
 sealed class CoverForm:Form {
  delegate bool EnumProc(IntPtr h,IntPtr p);
  [StructLayout(LayoutKind.Sequential)]struct Rect{public int l,t,r,b;}
  [DllImport("user32.dll")]static extern bool EnumWindows(EnumProc f,IntPtr p);
  [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out int pid);
  [DllImport("user32.dll")]static extern bool GetWindowRect(IntPtr h,out Rect r);
  [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")]static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]static extern IntPtr GetShellWindow();
  [DllImport("user32.dll")]static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")]static extern IntPtr GetWindowLongPtr(IntPtr h,int index);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder b,int n);
  [DllImport("user32.dll")]static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")]static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll")]static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
  [DllImport("user32.dll",SetLastError=true)]static extern bool GetLayeredWindowAttributes(IntPtr h,out uint key,out byte alpha,out uint flags);
  [StructLayout(LayoutKind.Sequential)]struct PointValue{public int x,y;}
  [DllImport("user32.dll")]static extern IntPtr WindowFromPoint(PointValue p);
  [DllImport("user32.dll")]static extern IntPtr GetAncestor(IntPtr h,uint flags);
  [DllImport("dwmapi.dll")]static extern int DwmGetWindowAttribute(IntPtr h,int key,out Rect value,int size);
  [DllImport("dwmapi.dll")]static extern int DwmSetWindowAttribute(IntPtr h,int key,ref int value,int size);
  readonly Dictionary<string,object> palette;readonly string eyebrow,primary,secondary,hintPrimary,hintSecondary,credit;readonly float focusX,focusY;
  readonly Process browser;readonly string folder,pausePath,themeId;readonly Image art;readonly Stopwatch clock=Stopwatch.StartNew();readonly System.Windows.Forms.Timer timer;readonly JavaScriptSerializer json=new JavaScriptSerializer();
  Bitmap background;RectangleF progress,skip;IntPtr tracked;Rectangle remembered;double lastForeground,lastMainVisible=-1000,shownAt=-1,changedAt,readyAt=-1,fadeAt=-1;float scale=1;bool finished,wasHidden,capture,saved,paintLogged,stackLogged;string reason="";NativeSurface surface;
  IntPtr SurfaceHandle{get{return surface==null?IntPtr.Zero:surface.Handle;}}bool SurfaceVisible{get{return surface!=null&&surface.Visible;}}
  static string TextOption(Dictionary<string,object> c,string key,string fallback){object v;if(!c.TryGetValue(key,out v)||!(v is string))return fallback;string s=(string)v;if(s.Length>120)throw new ArgumentException("Loading text is too long");foreach(char x in s)if(char.IsControl(x))throw new ArgumentException("Loading text contains controls");return s;}
  static float UnitOption(Dictionary<string,object> c,string key,float fallback){object v;if(!c.TryGetValue(key,out v))return fallback;float f=Convert.ToSingle(v);return float.IsNaN(f)||float.IsInfinity(f)?fallback:Math.Max(0,Math.Min(1,f));}
  static Image LoadArt(string path){var file=new FileInfo(path);if(!file.Exists||file.Length<16||file.Length>10485760)throw new ArgumentException("Invalid loading image size");using(var memory=new MemoryStream(File.ReadAllBytes(path)))using(var decoded=Image.FromStream(memory,false,true)){if((long)decoded.Width*decoded.Height>40000000)throw new ArgumentException("Loading image dimensions exceed limit");return new Bitmap(decoded);}}
  Color Tone(string key,int alpha=255){Color c=Color.FromArgb(244,239,231);try{if(palette!=null&&palette.ContainsKey(key))c=ColorTranslator.FromHtml((string)palette[key]);}catch{}return Color.FromArgb(alpha,c.R,c.G,c.B);}
  public CoverForm(Process browser,string folder,Dictionary<string,object> config){
   try{SetThreadDpiAwarenessContext(new IntPtr(-4));}catch{}
   palette=config.ContainsKey("colors")?config["colors"] as Dictionary<string,object>:null;
   eyebrow=TextOption(config,"eyebrow","");primary=TextOption(config,"primary","正在准备界面");secondary=TextOption(config,"secondary","");hintPrimary=TextOption(config,"hintPrimary","完成后将自动进入 Codex");hintSecondary=TextOption(config,"hintSecondary","");credit=TextOption(config,"credit","");
   focusX=UnitOption(config,"focusX",.5f);focusY=UnitOption(config,"focusY",.5f);
   this.browser=browser;this.folder=folder;pausePath=(string)config["pausePath"];themeId=(string)config["themeId"];art=LoadArt((string)config["artPath"]);capture=config.ContainsKey("capturePreview")&&(bool)config["capturePreview"];
   AutoScaleMode=AutoScaleMode.None;FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;ShowInTaskbar=false;Text="Codex skin";BackColor=Tone("background");
   // Alpha 254/255 is visually solid while allowing the covered Chromium
   // page to continue painting instead of becoming fully occluded.
   TopMost=true;Opacity=254d/255d;DoubleBuffered=true;SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer,true);
   timer=new System.Windows.Forms.Timer{Interval=16};timer.Tick+=(s,e)=>Tick();
  }
  protected override bool ShowWithoutActivation{get{return true;}}
  protected override CreateParams CreateParams{get{var p=base.CreateParams;p.ExStyle|=0x08000080;p.ExStyle&=~0x40000;return p;}}
  public void Prepare(){var ignored=Handle;surface=new NativeSurface(this);int yes=1;DwmSetWindowAttribute(SurfaceHandle,3,ref yes,4);Log("cover-armed",new{hwnd=SurfaceHandle.ToInt64(),showInTaskbar=false,activate=false,renderer="raw-native-surface"});timer.Start();}
  void Log(string name,object data){try{File.AppendAllText(Path.Combine(folder,"cover.jsonl"),json.Serialize(new{utc=DateTime.UtcNow.ToString("o"),eventName=name,data=data})+Environment.NewLine);}catch{}}
  bool MainWindow(IntPtr h,out Rectangle area){area=Rectangle.Empty;int pid;GetWindowThreadProcessId(h,out pid);if(pid!=browser.Id||!IsWindowVisible(h)||IsIconic(h))return false;var cls=new StringBuilder(128);GetClassName(h,cls,cls.Capacity);long style=GetWindowLongPtr(h,-16).ToInt64();if(cls.ToString()!="Chrome_WidgetWin_1"||(style&0x40000)==0||(style&0x10000)==0)return false;Rect r;if(DwmGetWindowAttribute(h,9,out r,16)!=0&&!GetWindowRect(h,out r))return false;if(r.r-r.l<300||r.b-r.t<200)return false;area=Rectangle.Intersect(Rectangle.FromLTRB(r.l,r.t,r.r,r.b),SystemInformation.VirtualScreen);return area.Width>=300&&area.Height>=200;}
  bool Ready(){try{var file=Path.Combine(folder,"ready.json");if(!File.Exists(file)||new FileInfo(file).Length>16384)return false;var r=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file));var identity=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(folder,"identity.json")));return Convert.ToInt32(r["pid"])==browser.Id&&(string)r["themeId"]==themeId&&(string)r["browserId"]==(string)identity["browserId"]&&(bool)r["ready"];}catch{return false;}}
  bool DesktopForeground(IntPtr h){if(h==IntPtr.Zero||h==GetShellWindow()||h==GetDesktopWindow())return true;var name=new StringBuilder(128);GetClassName(h,name,name.Capacity);string cls=name.ToString();return cls=="Progman"||cls=="WorkerW"||cls=="Shell_TrayWnd"||cls=="Shell_SecondaryTrayWnd";}
  void Tick(){try{
   double now=clock.Elapsed.TotalMilliseconds;
   if(finished)return;
   if(browser.HasExited){Finish("browser-exited",false);return;}
   if(File.Exists(pausePath)||!File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"loading-config.json"))){Finish("loading-disabled",false);return;}
   if(now>35000||(shownAt>=0&&now-shownAt>20000)){Finish("timeout",false);return;}
   if(fadeAt>=0){double alpha=1-(now-fadeAt)/180;if(alpha<=0){Finish(reason,false);return;}if(surface!=null)surface.SetAlpha((byte)Math.Max(1,Math.Min(254,alpha*254)));return;}
   IntPtr fg=GetForegroundWindow();int fgPid;GetWindowThreadProcessId(fg,out fgPid);bool foreground=fgPid==browser.Id||fg==SurfaceHandle;
   Rectangle area;IntPtr candidate=IntPtr.Zero;Rectangle candidateArea=Rectangle.Empty;
   if(fgPid==browser.Id&&MainWindow(fg,out area)){candidate=fg;candidateArea=area;}
   else if(tracked!=IntPtr.Zero&&MainWindow(tracked,out area)){candidate=tracked;candidateArea=area;}
   else EnumWindows((h,p)=>{Rectangle a;if(MainWindow(h,out a)){candidate=h;candidateArea=a;return false;}return true;},IntPtr.Zero);
   if(foreground)lastForeground=now;
   bool handover=DesktopForeground(fg)&&shownAt>=0&&now-lastForeground<600;
   if(candidate!=IntPtr.Zero){
    lastMainVisible=now;
    if(candidate!=tracked){Log("target-window-changed",new{from=tracked.ToInt64(),to=candidate.ToInt64(),rect=new[]{candidateArea.Left,candidateArea.Top,candidateArea.Right,candidateArea.Bottom}});tracked=candidate;changedAt=now;}
    if(remembered.IsEmpty)remembered=candidateArea;
    else if(Math.Abs(remembered.Left-candidateArea.Left)<=8&&Math.Abs(remembered.Top-candidateArea.Top)<=8&&Math.Abs(remembered.Right-candidateArea.Right)<=8&&Math.Abs(remembered.Bottom-candidateArea.Bottom)<=8)remembered=Rectangle.Union(remembered,candidateArea);
    else remembered=candidateArea;
    float dpi=1;try{dpi=GetDpiForWindow(candidate)/96f;}catch{}if(dpi>0&&Math.Abs(scale-dpi)>.01){scale=dpi;DisposeBackground();}
   }
   bool display=!remembered.IsEmpty&&(candidate!=IntPtr.Zero||(!IsIconic(tracked)&&now-lastMainVisible<600));
   if(display){
    // Restore our own surface's order before an expensive resize/repaint.
    // While Codex is foreground, a temporary topmost cover prevents a new
    // normal replacement window overtaking it between timer ticks.
    surface.Restack(candidate,foreground||handover);
    if(Bounds!=remembered){Bounds=remembered;DisposeBackground();}
    EnsureBackground();
    bool previouslyVisible=SurfaceVisible;surface.Display(remembered,candidate,foreground||handover);
    if(!previouslyVisible){if(shownAt<0)shownAt=now;Log(wasHidden?"cover-resumed":"cover-shown",new{hwnd=SurfaceHandle.ToInt64(),rect=new[]{Left,Top,Right,Bottom},foregroundPid=fgPid});wasHidden=false;}
    if(!stackLogged&&now-shownAt>350){stackLogged=true;uint key,flags;byte alpha;bool layered=GetLayeredWindowAttributes(SurfaceHandle,out key,out alpha,out flags);IntPtr at=GetAncestor(WindowFromPoint(new PointValue{x=Left+Width/4,y=Top+Height*35/100}),2);Log("cover-stack-check",new{exStyle=GetWindowLongPtr(SurfaceHandle,-20).ToInt64(),layeredAttributes=layered,alpha=alpha,flags=flags,topWindowAtSample=at.ToInt64(),hwnd=SurfaceHandle.ToInt64()});}
    surface.Repaint(Rectangle.Ceiling(progress));
   }else if(SurfaceVisible){surface.HideSurface();wasHidden=true;Log("cover-hidden-no-main-window",new{foregroundPid=fgPid});}
   if(candidate!=IntPtr.Zero&&Ready()){
    if(readyAt<0){readyAt=now;Log("underlying-theme-ready",new{hwnd=candidate.ToInt64()});}
    if(now-readyAt>=400&&now-changedAt>=300&&(shownAt<0||now-shownAt>=650))Finish("theme-ready",SurfaceVisible);
   }else readyAt=-1;
  }catch(Exception e){Log("cover-error",new{error=e.Message});Finish("cover-error",false);}}
  public void Finish(string why,bool fade){if(finished)return;if(fade&&fadeAt<0){reason=why;fadeAt=clock.Elapsed.TotalMilliseconds;return;}if(fadeAt>=0&&fade)return;finished=true;timer.Stop();Log("cover-closed",new{reason=why,elapsedMs=clock.Elapsed.TotalMilliseconds});if(surface!=null)surface.Dispose();Close();}
  void DisposeBackground(){if(background!=null){background.Dispose();background=null;}}
  static GraphicsPath Rounded(RectangleF r,float radius){var p=new GraphicsPath();float d=radius*2;p.AddArc(r.Left,r.Top,d,d,180,90);p.AddArc(r.Right-d,r.Top,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.Left,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;}
  void TextAt(Graphics g,string text,string family,float size,Color color,float x,float y){if(String.IsNullOrEmpty(text))return;using(var font=new Font(family,size*scale,FontStyle.Regular,GraphicsUnit.Pixel))using(var brush=new SolidBrush(color))g.DrawString(text,font,brush,x,y);}
  void EnsureBackground(){if(background!=null||ClientSize.Width<2||ClientSize.Height<2)return;int w=ClientSize.Width,h=ClientSize.Height;background=new Bitmap(w,h,PixelFormat.Format32bppArgb);using(var g=Graphics.FromImage(background)){
    g.SmoothingMode=SmoothingMode.AntiAlias;g.TextRenderingHint=TextRenderingHint.AntiAliasGridFit;g.Clear(Tone("background"));
    var dest=new RectangleF(w*.29f,0,w*.71f,h);float zoom=Math.Max(dest.Width/art.Width,dest.Height/art.Height),sw=dest.Width/zoom,sh=dest.Height/zoom;var src=new RectangleF((art.Width-sw)*focusX,(art.Height-sh)*focusY,sw,sh);g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(art,dest,src,GraphicsUnit.Pixel);
    using(var wash=new LinearGradientBrush(new Rectangle(0,0,w,h),Color.White,Color.White,0f)){wash.InterpolationColors=new ColorBlend{Positions=new[]{0f,.28f,.65f,1f},Colors=new[]{Tone("background",250),Tone("background",238),Tone("background",49),Tone("background",13)}};g.FillRectangle(wash,0,0,w,h);}
    float inset=24*scale;using(var pen=new Pen(Tone("secondary",90),scale))using(var border=Rounded(new RectangleF(inset,inset,Math.Max(1,w-2*inset),Math.Max(1,h-2*inset)),12*scale))g.DrawPath(pen,border);
    float left=Math.Max(38*scale,Math.Min(140*scale,w*.08f));float top=h*.44f-100*scale;
    TextAt(g,eyebrow,"Segoe UI",9,Tone("accentAlt"),left,top);
    TextAt(g,"✧","Segoe UI Symbol",29,Tone("secondary"),left,top+37*scale);using(var pen=new Pen(Tone("line"),scale))g.DrawLine(pen,left+43*scale,top+60*scale,left+112*scale,top+60*scale);
    TextAt(g,primary,"Microsoft YaHei UI",12,Tone("muted"),left,top+101*scale);
    TextAt(g,secondary,"Microsoft YaHei UI",10,Tone("muted",220),left,top+124*scale);
    progress=new RectangleF(left,top+161*scale,174*scale,2*scale);using(var brush=new SolidBrush(Tone("line")))g.FillRectangle(brush,progress);
    TextAt(g,hintPrimary,"Microsoft YaHei UI",10,Tone("muted"),left,top+177*scale);
    TextAt(g,hintSecondary,"Microsoft YaHei UI",9,Tone("muted",220),left,top+196*scale);
    TextAt(g,credit,"Microsoft YaHei UI",10,Tone("muted"),left,h-66*scale);
    skip=new RectangleF(w-132*scale,h-74*scale,96*scale,29*scale);using(var path=Rounded(skip,14*scale))using(var fill=new SolidBrush(Tone("panel",238)))using(var pen=new Pen(Tone("accent",110),scale)){g.FillPath(fill,path);g.DrawPath(pen,path);}TextAt(g,"暂时跳过","Microsoft YaHei UI",10,Tone("muted"),skip.Left+23*scale,skip.Top+6*scale);
   }if(capture&&!saved){saved=true;try{background.Save(Path.Combine(folder,"native-cover-preview.png"),ImageFormat.Png);}catch{}}}
  void PaintCover(Graphics graphics){EnsureBackground();if(background==null)return;graphics.DrawImageUnscaled(background,0,0);float x=progress.Left+(float)((clock.Elapsed.TotalMilliseconds%1900)/1900*(progress.Width*1.45)-progress.Width*.45);var bar=RectangleF.Intersect(progress,new RectangleF(x,progress.Top,progress.Width*.45f,progress.Height));if(bar.Width>0)using(var brush=new SolidBrush(Tone("accentAlt")))graphics.FillRectangle(brush,bar);if(!paintLogged){paintLogged=true;Log("cover-first-paint",new{width=ClientSize.Width,height=ClientSize.Height});}}
  protected override void OnPaint(PaintEventArgs e){PaintCover(e.Graphics);}
  protected override void OnMouseMove(MouseEventArgs e){Cursor=skip.Contains(e.Location)?Cursors.Hand:Cursors.Default;base.OnMouseMove(e);}
  protected override void OnMouseUp(MouseEventArgs e){if(e.Button==MouseButtons.Left&&skip.Contains(e.Location))Finish("user-skipped",false);base.OnMouseUp(e);}
  protected override void Dispose(bool disposing){if(disposing){if(surface!=null)surface.Dispose();timer.Dispose();DisposeBackground();art.Dispose();}base.Dispose(disposing);}
  sealed class NativeSurface:NativeWindow,IDisposable {
   [StructLayout(LayoutKind.Sequential)]struct PaintStruct{public IntPtr dc;public int erase;public Rect paint;public int restore,update;[MarshalAs(UnmanagedType.ByValArray,SizeConst=32)]public byte[] reserved;}
   [DllImport("user32.dll")]static extern IntPtr BeginPaint(IntPtr h,out PaintStruct paint);
   [DllImport("user32.dll")]static extern bool EndPaint(IntPtr h,ref PaintStruct paint);
   [DllImport("user32.dll")]static extern bool InvalidateRect(IntPtr h,IntPtr rect,bool erase);
   [DllImport("user32.dll",EntryPoint="InvalidateRect")]static extern bool InvalidateArea(IntPtr h,ref Rect rect,bool erase);
   [DllImport("user32.dll")]static extern bool UpdateWindow(IntPtr h);
   [DllImport("user32.dll")]static extern bool ShowWindow(IntPtr h,int command);
   [DllImport("user32.dll")]static extern bool SetLayeredWindowAttributes(IntPtr h,uint key,byte alpha,uint flags);
   readonly CoverForm owner;readonly BufferedGraphicsContext buffers=new BufferedGraphicsContext();BufferedGraphics frame;Size frameSize;Rectangle position;public bool Visible{get;private set;}bool disposed;
   public NativeSurface(CoverForm owner){this.owner=owner;CreateHandle(new CreateParams{Caption="Codex skin",Style=unchecked((int)0x80000000),ExStyle=0x08080080,X=0,Y=0,Width=1,Height=1});SetAlpha(254);}
   public void SetAlpha(byte alpha){if(Handle!=IntPtr.Zero)SetLayeredWindowAttributes(Handle,0,alpha,2);}
      [DllImport("user32.dll")]static extern IntPtr GetWindow(IntPtr h,uint command);
   IntPtr StackAfter(IntPtr target,bool foreground,out bool unchanged){
    bool topmost=(GetWindowLongPtr(Handle,-20).ToInt64()&8)!=0;
    if(foreground){unchanged=topmost;return new IntPtr(-1);}
    if(topmost)SetWindowPos(Handle,new IntPtr(-2),0,0,0,0,0x613);
    IntPtr after=target==IntPtr.Zero?Handle:GetWindow(target,3);
    unchanged=after==Handle;
    if(after!=IntPtr.Zero&&after!=Handle&&(GetWindowLongPtr(after,-20).ToInt64()&8)!=0)after=IntPtr.Zero;
    return after;
   }
   public void Restack(IntPtr target,bool foreground){if(!Visible)return;bool unchanged;IntPtr after=StackAfter(target,foreground,out unchanged);if(!unchanged)SetWindowPos(Handle,after,0,0,0,0,0x613);}
   public void Display(Rectangle r,IntPtr target,bool foreground){
    bool first=!Visible;IntPtr after=IntPtr.Zero;uint flags=0x650;
    // Pin only while Codex owns foreground (or its short desktop handoff).
    // In background, retain normal z-order immediately above Codex.
    bool unchanged;after=StackAfter(target,foreground,out unchanged);if(unchanged)flags|=4;
    if(!first&&position==r&&(flags&4)!=0)return;
    if(position==r)flags|=3;
    if(!first)flags&=~0x40u;
    SetWindowPos(Handle,after,r.X,r.Y,r.Width,r.Height,flags);Visible=true;position=r;
    if(first){InvalidateRect(Handle,IntPtr.Zero,false);UpdateWindow(Handle);}
   }
   public void HideSurface(){if(Handle!=IntPtr.Zero)ShowWindow(Handle,0);Visible=false;}
   public void Repaint(Rectangle r){if(Handle==IntPtr.Zero)return;r.Inflate(2,2);var dirty=new Rect{l=r.Left,t=r.Top,r=r.Right,b=r.Bottom};InvalidateArea(Handle,ref dirty,false);}
   protected override void WndProc(ref Message m){
    if(m.Msg==0x000F){PaintStruct p;IntPtr dc=BeginPaint(Handle,out p);try{
     // DoubleBuffered on the hidden coordinator Form does not apply to this
     // NativeWindow. Compose the dirty region offscreen, then copy once so
     // the background-only intermediate frame is never presented.
     Size size=owner.ClientSize;
     if(size.Width>0&&size.Height>0&&dc!=IntPtr.Zero){
      bool resized=frame==null||frameSize!=size;
      if(resized){if(frame!=null)frame.Dispose();buffers.MaximumBuffer=new Size(size.Width+1,size.Height+1);frame=buffers.Allocate(dc,new Rectangle(Point.Empty,size));frameSize=size;}
      var dirty=resized?new Rectangle(Point.Empty,size):Rectangle.FromLTRB(p.paint.l,p.paint.t,p.paint.r,p.paint.b);
      frame.Graphics.ResetClip();frame.Graphics.SetClip(dirty);owner.PaintCover(frame.Graphics);frame.Render(dc);
     }
    }finally{EndPaint(Handle,ref p);}m.Result=IntPtr.Zero;return;}
    if(m.Msg==0x0014){m.Result=new IntPtr(1);return;}
    if(m.Msg==0x0021){m.Result=new IntPtr(3);return;}
    if(m.Msg==0x0202){long value=m.LParam.ToInt64();var point=new Point(unchecked((short)(value&65535)),unchecked((short)((value>>16)&65535)));RectangleF skipArea=owner.skip;if(skipArea.Contains(point))owner.Finish("user-skipped",false);m.Result=IntPtr.Zero;return;}
    if(m.Msg==0x0010){owner.Finish("user-closed",false);m.Result=IntPtr.Zero;return;}
    base.WndProc(ref m);
   }
   public void Dispose(){if(disposed)return;disposed=true;Visible=false;if(Handle!=IntPtr.Zero)DestroyHandle();if(frame!=null){frame.Dispose();frame=null;}buffers.Dispose();}
  }
 }
}
