// Per-package pre-window activation. Registers the current-user package activation callback; does not modify app files.
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class ImageSkinPrelaunch {
    [ComImport, Guid("F27C3930-8029-4AD1-94E3-3DBA417810C1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPackageDebugSettings {
        void EnableDebugging([MarshalAs(UnmanagedType.LPWStr)] string package, [MarshalAs(UnmanagedType.LPWStr)] string debugger, IntPtr environment);
        void DisableDebugging([MarshalAs(UnmanagedType.LPWStr)] string package);
    }
    private static IPackageDebugSettings settings;
    public static void Register(string package, string broker) {
        if (!Regex.IsMatch(package, @"^OpenAI\.Codex_\d+\.\d+\.\d+\.\d+_x64__2p2nqsd0c76g0$")) throw new ArgumentException("Unexpected package");
        if (!File.Exists(broker) || !Path.GetFullPath(broker).Equals(Path.Combine(Path.GetDirectoryName(typeof(ImageSkinPrelaunch).Assembly.Location),"ImageSkinLaunchBroker.exe"), StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Unexpected broker");
        if (settings == null) settings = (IPackageDebugSettings)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("B1AEC16F-2383-4852-B0E9-8F0B1DC66B4D")));
        settings.EnableDebugging(package, "\"" + broker + "\"", IntPtr.Zero);
    }
    public static void Unregister(string package) {
        if (!Regex.IsMatch(package, @"^OpenAI\.Codex_\d+\.\d+\.\d+\.\d+_x64__2p2nqsd0c76g0$")) throw new ArgumentException("Unexpected package");
        var s = settings ?? (IPackageDebugSettings)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("B1AEC16F-2383-4852-B0E9-8F0B1DC66B4D")));
        s.DisableDebugging(package);
    }
}
