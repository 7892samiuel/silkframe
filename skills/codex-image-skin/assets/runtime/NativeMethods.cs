using System;using System.Net;using System.Net.Sockets;using System.Runtime.InteropServices;
public static class ImageSkinNative {
 [DllImport("kernel32.dll",SetLastError=true)]public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll")]public static extern bool CloseHandle(IntPtr handle);
 public static int FreePort(){for(int port=9335;port<9435;port++)try{var listener=new TcpListener(IPAddress.Loopback,port);listener.Server.ExclusiveAddressUse=true;listener.Start();listener.Stop();return port;}catch(SocketException){}throw new InvalidOperationException("No free loopback skin port");}
}
