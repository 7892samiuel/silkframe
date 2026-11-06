function Register-ImageSkinPrelaunch($context){
 $root=$PSScriptRoot
 $broker=Join-Path $root 'ImageSkinLaunchBroker.exe'
 $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\PackagedAppXDebug\'+$context.App.PackageFullName
 if(Test-Path -LiteralPath $key){$old=[string](Get-Item -LiteralPath $key).GetValue('');if($old -and $old -cne ('"'+$broker+'"') -and $old -cne ('"'+(Join-Path $root 'ImageSkinLaunchBroker.exe')+'"')){throw 'A different startup callback owns this package; preserved.'}}
 $aliases=Join-Path $root '.arg';$ownerFile=Join-Path $aliases 'owner.json';$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if(Test-Path -LiteralPath $aliases){
  $info=Get-Item -LiteralPath $aliases;if($info.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Alias root is redirected; preserved.'}
  if(-not(Test-Path -LiteralPath $ownerFile)){throw 'Unowned argument alias directory; preserved.'}
  $owner=Get-Content -LiteralPath $ownerFile -Raw|ConvertFrom-Json;if($owner.sid -ne $sid -or $owner.root -ne $root){throw 'Argument alias ownership differs.'}
 }else{[IO.Directory]::CreateDirectory($aliases)|Out-Null;@{sid=$sid;root=$root}|ConvertTo-Json|Set-Content -LiteralPath $ownerFile -Encoding UTF8}
 $officialDir=Split-Path -Parent $context.App.Executable;$alias=$null
 foreach($entry in Get-ChildItem -LiteralPath $aliases -Directory -Force){if($entry.Name -match '^\d{4}$' -and $entry.LinkType -eq 'Junction' -and @($entry.Target).Count -eq 1 -and @($entry.Target)[0] -eq $officialDir){$alias=$entry.FullName;break}}
 if(-not $alias){for($i=1;$i -le 9999;$i++){$candidate=Join-Path $aliases $i.ToString('D4');if(-not(Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue)){$alias=$candidate;break}};if(-not $alias){throw 'No free alias slot.'};New-Item -ItemType Junction -Path $alias -Target $officialDir|Out-Null}
 $argumentAlias=Join-Path $alias 'ChatGPT.exe'
 if($argumentAlias.Length+' --remote-debugging-port=65535'.Length -gt $context.App.Executable.Length){throw 'Absolute alias will not fit the native startup buffer.'}
 $config=@{schemaVersion=1;package=$context.App.PackageFullName;sid=$sid;officialImage=$context.App.Executable;argumentAlias=$argumentAlias;profileMode='native-default'}
 Write-DreamSkinUtf8FileAtomically -Path (Join-Path $root 'native-startup-config.json') -Content ($config|ConvertTo-Json)
 if(-not ('ImageSkinPrelaunch' -as [type])){Add-Type -Path (Join-Path $root 'ImageSkinPrelaunch.dll')}
 [ImageSkinPrelaunch]::Register($context.App.PackageFullName,$broker)
 Write-DreamSkinUtf8FileAtomically -Path (Join-Path $root 'prelaunch-registration.json') -Content (@{schemaVersion=1;package=$context.App.PackageFullName;broker=$broker;startupMode='native-in-place';registered=(Get-Date).ToString('o')}|ConvertTo-Json)
 Save-OriginalStatus 'prelaunch-ready' 'Original activation receives its port in place; native default profile, no spawned browser or forced restart.'
}
