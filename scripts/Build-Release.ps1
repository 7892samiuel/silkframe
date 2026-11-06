[CmdletBinding()]
param([switch]$SkipTests)
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
if(-not $SkipTests){& (Join-Path $PSScriptRoot 'Test-Release.ps1')}
$version=(Get-Content -LiteralPath (Join-Path $repository VERSION) -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$'){throw 'Invalid release version'}
$output=Join-Path $repository dist;[IO.Directory]::CreateDirectory($output)|Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Archive([string]$destination,[string]$prefix,[string]$base,[IO.FileInfo[]]$files){
 $temporary=$destination+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew)
 try{
  $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{foreach($file in $files|Sort-Object FullName){
   if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Archive input cannot be a reparse point'}
   if($file.Extension -in @('.exe','.dll','.log','.jsonl')){throw ('Runtime artifact in release input: '+$file.Name)}
   $name=$prefix+'/'+$file.FullName.Substring($base.Length).TrimStart('\','/').Replace('\','/')
   $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
   $entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
   $source=[IO.File]::OpenRead($file.FullName);$target=$entry.Open()
   try{$source.CopyTo($target)}finally{$target.Dispose();$source.Dispose()}
  }}finally{$zip.Dispose()}
 }finally{$stream.Dispose()}
 $backup=$destination+'.replace-'+[guid]::NewGuid().ToString('N')+'.bak'
 try{if(Test-Path -LiteralPath $destination){[IO.File]::Replace($temporary,$destination,$backup)}else{[IO.File]::Move($temporary,$destination)}}
 finally{foreach($ownedFile in @($temporary,$backup)){if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ownedFile)) -eq [IO.Path]::GetDirectoryName($destination) -and [IO.File]::Exists($ownedFile)){[IO.File]::Delete($ownedFile)}}}
}
$skill=Join-Path $repository 'skills\codex-image-skin'
$skillFiles=@(Get-ChildItem -LiteralPath $skill -File -Recurse)
$skillZip=Join-Path $output ('silkframe-skill-v'+$version+'.zip')
Archive $skillZip 'codex-image-skin' $skill $skillFiles
$files=@(Get-ChildItem -LiteralPath $repository -File -Force|Where-Object Name -in @('README.md','README.zh-CN.md','LICENSE','THIRD-PARTY-NOTICES.md','VERSION','.gitignore','.gitattributes'))
foreach($scope in @('skills','scripts','tests','docs','.github')){$files+=@(Get-ChildItem -LiteralPath (Join-Path $repository $scope) -File -Recurse -Force)}
$sourceZip=Join-Path $output ('silkframe-source-v'+$version+'.zip')
Archive $sourceZip 'silkframe' $repository $files
$lines=@($skillZip,$sourceZip)|ForEach-Object{(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($_)}
[IO.File]::WriteAllLines((Join-Path $output SHA256SUMS.txt),$lines,[Text.UTF8Encoding]::new($false))
@{version=$version;skillZip=$skillZip;sourceZip=$sourceZip;checksums=(Join-Path $output SHA256SUMS.txt);personalRuntimeIncluded=$false}|ConvertTo-Json
