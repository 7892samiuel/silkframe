// Independent implementation of bounded, in-place initial argument editing.
// The process is created suspended by Windows. No code or package files change.
using System;using System.IO;using System.Text;using System.Runtime.InteropServices;using System.Text.RegularExpressions;using Microsoft.Win32.SafeHandles;
public static class NativeStartupArguments {
 [StructLayout(LayoutKind.Sequential)]struct Info{public IntPtr reserved,peb,affinity,priority,pid,parent;}
 [StructLayout(LayoutKind.Sequential)]struct TextRef{public ushort bytes,capacity;public IntPtr pointer;}
 [StructLayout(LayoutKind.Sequential)]struct Parameters{[MarshalAs(UnmanagedType.ByValArray,SizeConst=16)]public byte[] reserved;[MarshalAs(UnmanagedType.ByValArray,SizeConst=10)]public IntPtr[] pointers;public TextRef image,command;}
 [StructLayout(LayoutKind.Sequential)]struct Peb{[MarshalAs(UnmanagedType.ByValArray,SizeConst=4)]public byte[] flags;[MarshalAs(UnmanagedType.ByValArray,SizeConst=2)]public IntPtr[] reserved;public IntPtr loader,parameters;}
 [DllImport("ntdll.dll")]static extern int NtQueryInformationProcess(IntPtr p,int c,out Info i,int length,out int result);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool ReadProcessMemory(IntPtr p,IntPtr a,byte[] b,IntPtr n,out IntPtr used);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool WriteProcessMemory(IntPtr p,IntPtr a,byte[] b,IntPtr n,out IntPtr used);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFile(string p,uint access,uint sharing,IntPtr security,uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint n,uint flags);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool QueryFullProcessImageName(IntPtr p,uint flags,StringBuilder name,ref int length);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool IsWow64Process(IntPtr p,out bool wow64);
 static T Structure<T>(byte[] b){var pin=GCHandle.Alloc(b,GCHandleType.Pinned);try{return (T)Marshal.PtrToStructure(pin.AddrOfPinnedObject(),typeof(T));}finally{pin.Free();}}
 static byte[] Read(IntPtr p,IntPtr a,int n){var b=new byte[n];IntPtr used;if(!ReadProcessMemory(p,a,b,(IntPtr)n,out used)||used.ToInt64()!=n)throw new InvalidOperationException("Cannot read initial arguments");return b;}
 static void Write(IntPtr p,IntPtr a,byte[] b){IntPtr used;if(!WriteProcessMemory(p,a,b,(IntPtr)b.Length,out used)||used.ToInt64()!=b.Length)throw new InvalidOperationException("Cannot write initial arguments");}
 public static string Canonical(string p){using(var h=CreateFile(p,0,7,IntPtr.Zero,3,0,IntPtr.Zero)){if(h.IsInvalid)throw new IOException("Cannot resolve executable alias");var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,b,(uint)b.Capacity,0);if(n==0||n>=b.Capacity)throw new IOException("Cannot resolve executable identity");return b.ToString();}}
 static TextRef Locate(IntPtr p,string image,out IntPtr descriptor){
  if(IntPtr.Size!=8)throw new PlatformNotSupportedException("x64 required");bool wow;if(!IsWow64Process(p,out wow)||wow)throw new PlatformNotSupportedException("Target is not x64");
  var actual=new StringBuilder(32768);int n=actual.Capacity;if(!QueryFullProcessImageName(p,0,actual,ref n)||!String.Equals(Canonical(actual.ToString()),Canonical(image),StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Actual executable does not match expected image");
  Info i;int used;if(NtQueryInformationProcess(p,0,out i,Marshal.SizeOf(typeof(Info)),out used)!=0)throw new InvalidOperationException("Initial process layout unavailable");
  var peb=Structure<Peb>(Read(p,i.peb,Marshal.SizeOf(typeof(Peb))));var pars=Structure<Parameters>(Read(p,peb.parameters,Marshal.SizeOf(typeof(Parameters))));
  string parameterImage=ReadText(p,pars.image);if(parameterImage.StartsWith(@"\??\"))parameterImage=parameterImage.Substring(4);
  if(!String.Equals(Canonical(parameterImage),Canonical(image),StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Parameter executable identity mismatch");
  descriptor=IntPtr.Add(peb.parameters,Marshal.OffsetOf(typeof(Parameters),"command").ToInt32());return pars.command;
 }
 static string ReadText(IntPtr p,TextRef t){if(t.bytes==0||t.bytes%2!=0||t.capacity<t.bytes||t.capacity>32766||t.pointer==IntPtr.Zero)throw new InvalidOperationException("Initial argument descriptor invalid");return Encoding.Unicode.GetString(Read(p,t.pointer,t.bytes));}
 public static string ReadCommand(IntPtr p,string expectedImage){IntPtr descriptor;return ReadText(p,Locate(p,expectedImage,out descriptor));}
 public static string AddPort(IntPtr p,string image,string alias,int port){
  if(port<1024||port>65535)throw new ArgumentException("Invalid loopback port");
  if(!Path.IsPathRooted(alias)||!String.Equals(Canonical(alias),Canonical(image),StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Absolute alias must resolve to the same official image");
  IntPtr descriptor;TextRef old=Locate(p,image,out descriptor);string original=ReadText(p,old);
  if(Regex.IsMatch(original,@"(?:^|\s)--(?:type|remote-debugging[^=\s]*|user-data-dir)(?:=|\s|$)"))throw new InvalidOperationException("Explicit transport/profile arguments were preserved");
  if(!original.StartsWith("\""))throw new InvalidOperationException("Unquoted executable token preserved");int end=original.IndexOf('"',1);
  if(end<2||!String.Equals(Canonical(original.Substring(1,end-1)),Canonical(image),StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Executable argument identity mismatch");
  // Insert BEFORE protocol --single-argument, preserving its entire raw tail.
  string updated="\""+alias+"\" --remote-debugging-port="+port+original.Substring(end+1);var text=Encoding.Unicode.GetBytes(updated+"\0");
  if(text.Length>old.capacity)throw new InvalidOperationException("Original argument buffer has insufficient capacity; native arguments unchanged");
  byte[] saved=Read(p,old.pointer,old.capacity);byte[] oldLength=BitConverter.GetBytes(old.bytes);bool attempted=false;
  try{
   attempted=true;Write(p,old.pointer,text);Write(p,descriptor,BitConverter.GetBytes((ushort)(text.Length-2)));
   IntPtr verifyDescriptor;var current=Locate(p,image,out verifyDescriptor);
   if(current.pointer!=old.pointer||current.capacity!=old.capacity||ReadText(p,current)!=updated)throw new InvalidOperationException("In-place argument verification failed");
   return updated;
  }catch{
   if(attempted){Write(p,old.pointer,saved);Write(p,descriptor,oldLength);if(ReadCommand(p,image)!=original)throw new InvalidOperationException("Initial argument rollback could not be verified");}
   throw;
  }
 }
}
