[CmdletBinding()]
param(
 [string]$SourceDirectory,
 [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
if(-not $SourceDirectory){$SourceDirectory=Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\runtime'}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $compiler)){throw '.NET Framework x64 compiler is required.'}
$source=[IO.Path]::GetFullPath($SourceDirectory);$destination=[IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($destination)|Out-Null
if((Get-Item -LiteralPath $destination).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Build output must be an ordinary directory.'}
function Compile([string]$name,[string]$target,[string[]]$files,[string[]]$references){
 $arguments=@('/nologo','/optimize+','/platform:x64',('/target:'+$target),('/out:'+(Join-Path $destination $name)))
 $arguments+=@($references|ForEach-Object{'/r:'+$_})
 $arguments+=@($files|ForEach-Object{Join-Path $source $_})
 & $compiler @arguments
 if($LASTEXITCODE -ne 0){throw ('Compilation failed: '+$name)}
}
Compile 'ImageSkinPrelaunch.dll' 'library' @('ImageSkinPrelaunch.cs') @()
Compile 'ImageSkinHost.exe' 'winexe' @('ImageSkinHost.cs') @()
Compile 'ImageSkinLaunchBroker.exe' 'winexe' @('ImageSkinLaunchBroker.cs','NativeStartupArguments.cs','NativeShutdownGate.cs','NativeMethods.cs') @('System.Web.Extensions.dll','Microsoft.CSharp.dll')
Compile 'ImageSkinLoadingHost.exe' 'winexe' @('ImageSkinLoadingHost.cs','ImageSkinLoadingCover.cs','NativeStartupArguments.cs','NativeMethods.cs') @('System.Web.Extensions.dll','System.Windows.Forms.dll','System.Drawing.dll')
@{status='built';outputDirectory=$destination;binaries=@('ImageSkinPrelaunch.dll','ImageSkinHost.exe','ImageSkinLaunchBroker.exe','ImageSkinLoadingHost.exe')}|ConvertTo-Json
