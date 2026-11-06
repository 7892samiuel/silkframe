using System;using System.IO;class EchoFixture{static int Main(string[] args){File.WriteAllLines(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"echo-args.txt"),args);return 42;}}
