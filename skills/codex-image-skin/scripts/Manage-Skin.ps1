[CmdletBinding(SupportsShouldProcess=$true)]
param(
 [Parameter(Mandatory=$true)][ValidateSet('Doctor','Validate','Install','Apply','Status','Pause','Resume','Disable')][string]$Action,
 [string]$ThemeDirectory,[switch]$AllowRuntimeDownload
)
$env:PSModulePath="$env:WINDIR\System32\WindowsPowerShell\v1.0\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
$ErrorActionPreference='Stop'
$skillRoot=Split-Path -Parent $PSScriptRoot
$ownRoot=Join-Path $env:LOCALAPPDATA 'CodexImageSkin'
$dreamRoot=Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$vendorRoot=Join-Path $skillRoot 'assets\engine'
$markerPath=Join-Path $ownRoot 'installation.json'
$owned=$false
if(Test-Path -LiteralPath $markerPath){$marker=Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json;if($marker.product -cne 'codex-image-skin/1'){throw 'Unexpected installation marker; preserved.'};$owned=$true}
$stateRoot=if($owned){$ownRoot}elseif(Test-Path -LiteralPath (Join-Path $dreamRoot 'engine\scripts\common-windows.ps1')){$dreamRoot}else{$ownRoot}
$engineRoot=if(Test-Path -LiteralPath (Join-Path $stateRoot 'engine\scripts\common-windows.ps1')){Join-Path $stateRoot engine}else{$vendorRoot}
. (Join-Path $engineRoot 'scripts\common-windows.ps1')
. (Join-Path $skillRoot 'assets\runtime\ImageSkin-Injector.ps1')
. (Join-Path $skillRoot 'assets\runtime\Configure-Loading.ps1')
$proofRoot=Join-Path $ownRoot proofs
function Save-OriginalStatus([string]$state,[string]$detail){
 [IO.Directory]::CreateDirectory($proofRoot)|Out-Null
 @{state=$state;detail=$detail;pid=$PID;updated=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $proofRoot 'apply-status.json') -Encoding UTF8
}
function Get-NodeRuntime {
 $privateNode=Join-Path $ownRoot 'engine\runtime\node\node.exe'
 if($owned -and (Test-Path -LiteralPath $privateNode)){return Get-DreamSkinValidatedNodeRuntime -Path $privateNode}
 try{return Get-DreamSkinNodeRuntime}catch{
  $existing=Join-Path $dreamRoot 'engine\runtime\node\node.exe'
  if(Test-Path -LiteralPath $existing){return Get-DreamSkinValidatedNodeRuntime -Path $existing}
  throw
 }
}
function Get-Callback($app){
 $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\PackagedAppXDebug\'+$app.PackageFullName
 if(Test-Path -LiteralPath $key){return [string](Get-Item -LiteralPath $key).GetValue('')}
 return ''
}
function Get-Persistence($app){
 $callback=Get-Callback $app
 $broker=$null
 if($callback -match '^"([^"]+\.exe)"(?:\s.*)?$'){$broker=$Matches[1]}
 $candidates=@();$task=$null;$live=$false;$startupMode=$null;$nativeAlias=$null
 if($broker -and (Test-Path -LiteralPath $broker)){
  $controllerRoot=Split-Path -Parent $broker
  $proof=Join-Path $controllerRoot 'original-profile-proof.json'
  $registration=Join-Path $controllerRoot 'prelaunch-registration.json'
  if((Test-Path -LiteralPath $registration) -and ((Test-Path -LiteralPath $proof) -or $owned)){
   $registered=Get-Content -LiteralPath $registration -Raw|ConvertFrom-Json
   if($registered.package -eq $app.PackageFullName -and (Test-DreamSkinPathEqual $registered.broker $broker)){
    $startupMode=$registered.startupMode
    if($startupMode -ceq 'native-in-place'){
     $configPath=Join-Path $controllerRoot 'native-startup-config.json'
     if((Test-Path -LiteralPath $configPath) -and (Get-Item -LiteralPath $configPath).Length -le 16384){
      $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
      if($config.package -ceq $app.PackageFullName -and $config.sid -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and (Test-DreamSkinPathEqual $config.officialImage $app.Executable) -and $config.profileMode -ceq 'native-default' -and $config.argumentAlias -and [IO.Path]::IsPathRooted($config.argumentAlias)){$nativeAlias=[string]$config.argumentAlias}
     }
    }
    $service=New-Object -ComObject 'Schedule.Service';$service.Connect()
    foreach($candidate in $service.GetFolder('\').GetTasks(1)){
     foreach($a in $candidate.Definition.Actions){
      if($a.Type -eq 0 -and (Test-DreamSkinPathEqual (Split-Path -Parent $a.Path) $controllerRoot) -and [IO.Path]::GetFileName($a.Path) -like '*SkinHost.exe'){
       $candidates+=@{name=$candidate.Name;enabled=[bool]$candidate.Enabled;state=[int]$candidate.State;path=$a.Path}
       $hostProcesses=@(Get-CimInstance Win32_Process -Filter "Name='$([IO.Path]::GetFileName($a.Path))'" -ErrorAction SilentlyContinue|Where-Object{Test-DreamSkinPathEqual $_.ExecutablePath $a.Path})
       if($candidate.Enabled -and $candidate.State -eq 4 -and $hostProcesses.Count -eq 1){$task=$candidate.Name;$live=$true}
      }
     }
    }
   }
  }
 }
 [pscustomobject]@{configured=$live;callbackPresent=[bool]$callback;callback=$callback;task=$task;candidates=$candidates;startupMode=$startupMode;nativeAlias=$nativeAlias;kind=$(if($owned){'owned'}elseif($live){'reused-entry-helper'}elseif($callback){'foreign-or-unverified'}else{'none'})}
}
function Get-Context {
 $app=Get-DreamSkinCodexInstall
 if(-not(Test-Path -LiteralPath (Join-Path (Split-Path -Parent $app.Executable) 'owl-shell-runtime.json'))){throw 'This skill currently supports the Owl desktop runtime only.'}
 [pscustomobject]@{App=$app;Node=(Get-NodeRuntime);LogicalProfile=(Join-Path $env:APPDATA 'Codex\web\Codex');ProfileMode='legacy-explicit';StateRoot=$stateRoot}
}
function Assert-Theme([string]$directory,$node){
 $directory=[IO.Path]::GetFullPath($directory)
 $item=Get-Item -LiteralPath $directory
 if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Theme must be an ordinary directory.'}
 $files=@(Get-ChildItem -LiteralPath $directory -Force)
 if($files.Count -ne 3){throw 'Theme must contain exactly theme.json, theme.css, and its background image.'}
 foreach($f in $files){if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Nested directories and reparse points are not theme payloads.'}}
 $jsonFile=Join-Path $directory 'theme.json';if((Get-Item -LiteralPath $jsonFile).Length -gt 65536){throw 'Oversized theme JSON.'}
 $theme=Get-Content -LiteralPath $jsonFile -Raw -Encoding UTF8|ConvertFrom-Json
 if($theme.image -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.(?:png|jpg|jpeg|webp)$'){throw 'Unsupported theme image leaf.'}
 foreach($f in $files){if($f.Name -cnotin @('theme.json','theme.css',$theme.image)){throw 'Unknown theme payload.'}}
 $result=& $node.Path (Join-Path $engineRoot 'scripts\injector.mjs') --check-payload --theme-dir $directory
 if($LASTEXITCODE -ne 0){throw 'Engine payload/Safe CSS/image validation failed.'}
 $checked=$result|ConvertFrom-Json
 if(-not $checked.pass -or $checked.themeId -cne $theme.id){throw 'Theme payload did not validate.'}
 [pscustomobject]@{Directory=$directory;Theme=$theme;Validation=$checked}
}
function Get-LiveState($context){
 $state=Read-DreamSkinState -Path (Join-Path $stateRoot 'state.json')
 if($state -and -not(Test-DreamSkinPathEqual $state.themeDir (Join-Path $stateRoot 'active-theme'))){throw 'Saved state has an unexpected theme directory; preserved.'}
 $roots=@(Get-DreamSkinCodexProcesses -Codex $context.App|Where-Object{$_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine -match '--remote-debugging-port='})
 if($roots.Count -eq 0){return $null};if($roots.Count -ne 1){throw 'Multiple debugging browsers were preserved.'}
 $cmd=$roots[0].CommandLine
 if($cmd -match '--user-data-dir=(?:"([^"]+)"|([^\s]+))'){
  $profile=if($Matches[1]){$Matches[1]}else{$Matches[2]}
  if(-not(Test-DreamSkinPathEqual $profile $context.LogicalProfile)){throw 'Different explicit profile preserved.'}
  $context.ProfileMode='legacy-explicit'
 }else{
  $owner=Get-Persistence $context.App
  if(-not $owner.configured -or $owner.startupMode -cne 'native-in-place' -or -not $owner.nativeAlias -or -not $cmd.StartsWith(('"'+$owner.nativeAlias+'" '),[StringComparison]::OrdinalIgnoreCase)){throw 'Browser without an explicit profile has no verified native startup owner; preserved.'}
  $context.ProfileMode='native-default'
 }
 if($cmd -notmatch '--remote-debugging-port="?(\d+)'){return $null};$port=[int]$Matches[1]
 $identity=Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $context.App
 if(-not $identity){return $null}
 if(-not $state -or $state.browserId -cne $identity.BrowserId -or -not(Test-DreamSkinPathEqual $state.codexExe $context.App.Executable)){
  # Reopening creates a new browser GUID. Derive it again from the verified
  # official root and original profile, never trust a stale state file alone.
  $state=[pscustomobject]@{port=$port;browserId=$identity.BrowserId;injectorPid=$null;injectorStartedAt=$null}
 }
 [pscustomobject]@{State=$state;Identity=$identity}
}
function Register-SkinTask($context){
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
 $other=@($folder.GetTasks(1)|Where-Object Name -eq 'CodexImageSkin')
 if($other.Count -gt 1){throw 'Ambiguous task identity; preserved.'}
 if($other.Count -eq 1 -and ($other[0].Definition.Actions.Count -ne 1 -or -not(Test-DreamSkinPathEqual $other[0].Definition.Actions.Item(1).Path (Join-Path $ownRoot 'ImageSkinHost.exe')))){throw 'Another installation owns the task name; preserved.'}
 foreach($leaf in @('ImageSkinHost.exe','ImageSkinLaunchBroker.exe','ImageSkinPrelaunch.dll','ImageSkinLoadingHost.exe')){if(-not(Test-Path -LiteralPath (Join-Path $ownRoot $leaf))){throw ('Installed component missing: '+$leaf+'; no healthy-install claim.')}}
 $definition=$service.NewTask(0);$definition.RegistrationInfo.Description='Restore the selected local Codex image skin on original app launches.'
 $definition.Principal.UserId=[Security.Principal.WindowsIdentity]::GetCurrent().Name;$definition.Principal.LogonType=3;$definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true;$definition.Settings.Hidden=$true;$definition.Settings.ExecutionTimeLimit='PT0S';$definition.Settings.MultipleInstances=2
 $definition.Settings.DisallowStartIfOnBatteries=$false;$definition.Settings.StopIfGoingOnBatteries=$false
 $definition.Settings.RestartCount=2;$definition.Settings.RestartInterval='PT1M'
 $null=$definition.Triggers.Create(9)
 $periodic=$definition.Triggers.Create(1);$periodic.StartBoundary=(Get-Date).AddMinutes(1).ToString('s');$periodic.Repetition.Interval='PT1M'
 $a=$definition.Actions.Create(0);$a.Path=Join-Path $ownRoot 'ImageSkinHost.exe';$a.WorkingDirectory=$ownRoot
 $stop=Join-Path $ownRoot 'original-profile.stop';if(Test-Path -LiteralPath $stop){Remove-Item -LiteralPath $stop}
 & (Join-Path $ownRoot 'Register-Loading.ps1')|Out-Null
 $task=$folder.RegisterTaskDefinition('CodexImageSkin',$definition,6,$null,$null,3,$null);$null=$task.Run($null)
 $deadline=[DateTime]::UtcNow.AddSeconds(18)
 do{
  Start-Sleep -Milliseconds 350
  $health=Get-Persistence $context.App
  if($health.configured){return $health}
 }while([DateTime]::UtcNow -lt $deadline)
 throw 'Runtime files and task are saved, but actual callback/host readiness did not pass. Run Doctor and retry Install to repair; current Codex was not closed.'
}
function Install-Runtime($context){
 $callback=Get-Callback $context.App
 $expected='"'+(Join-Path $ownRoot 'ImageSkinLaunchBroker.exe')+'"'
 if($callback -and $callback -cne $expected){throw 'Another package startup callback exists. Reuse or explicitly migrate its installation; it was not overwritten.'}
 if(-not(Test-Path -LiteralPath (Join-Path (Split-Path -Parent $context.App.Executable) 'owl-shell-runtime.json'))){throw 'This installer supports the Owl runtime only.'}
 if($owned){
  if($marker.runtimeMode -cne 'native-in-place'){throw 'An earlier runtime is installed. Disable that version before migrating; existing files and callback were preserved.'}
  if(-not $PSCmdlet.ShouldProcess($ownRoot,'Verify/repair the owned automatic recovery task')){return @{status='planned';runtimeRoot=$ownRoot}}
  $health=Register-SkinTask $context
  return @{status='installed-verified';runtimeRoot=$ownRoot;persistence=$health;coldLaunchTested=$false}
 }
 if(Test-Path -LiteralPath $dreamRoot){throw 'An existing Dream Skin installation was found. Reuse its working persistence; do not install a competing controller.'}
 if(Test-Path -LiteralPath $ownRoot){throw 'An unmarked runtime directory exists; it was preserved.'}
 $profile=Join-Path $env:LOCALAPPDATA ('Packages\'+$context.App.PackageFamilyName+'\LocalCache\Roaming\Codex\web\Codex')
 if(-not(Test-Path -LiteralPath (Join-Path $profile 'Local State')) -or -not(Test-Path -LiteralPath (Join-Path $profile 'Default\Preferences'))){throw 'Open the official app once before enabling persistence; its existing profile is incomplete.'}
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect()
 if(@($service.GetFolder('\').GetTasks(1)|Where-Object Name -eq 'CodexImageSkin').Count){throw 'The task name already exists without this installation marker; no runtime files were committed.'}
 if(-not $PSCmdlet.ShouldProcess($ownRoot,'Install current-user skin runtime, package callback, and login/recovery task')){return @{status='planned';runtimeRoot=$ownRoot;originalEntryPreserved=$true}}
 $stage=$ownRoot+'.install-'+[guid]::NewGuid().ToString('N');[IO.Directory]::CreateDirectory($stage)|Out-Null
 try{
  $manifest=Get-Content -LiteralPath (Join-Path $skillRoot 'assets\engine-files.json') -Raw|ConvertFrom-Json
  foreach($p in $manifest.files.PSObject.Properties){
   if($p.Name -match '(^/|\.\.|:|\\)'){throw 'Invalid engine manifest path.'}
   $payloadFile=Join-Path $vendorRoot $p.Name
   if((Get-FileHash -LiteralPath $payloadFile -Algorithm SHA256).Hash -ine $p.Value){throw 'Vendored engine integrity check failed.'}
  }
  Copy-Item -LiteralPath $vendorRoot -Destination (Join-Path $stage engine) -Recurse
  foreach($f in Get-ChildItem (Join-Path $skillRoot 'assets\runtime') -File){Copy-Item -LiteralPath $f.FullName -Destination $stage}
  $nodeDir=Join-Path $stage 'engine\runtime\node';[IO.Directory]::CreateDirectory($nodeDir)|Out-Null
  $nodePath=Join-Path $nodeDir node.exe
  if($context.Node){Copy-Item -LiteralPath $context.Node.Path -Destination $nodePath}
  else{
   if(-not $AllowRuntimeDownload){throw 'Signed Node 22+ is unavailable. AllowRuntimeDownload is required to fetch the pinned runtime.'}
   Invoke-WebRequest -UseBasicParsing -Uri 'https://nodejs.org/dist/v22.23.1/win-x64/node.exe' -OutFile $nodePath
   if((Get-FileHash -LiteralPath $nodePath -Algorithm SHA256).Hash -cne 'F8D162C0641DCEE512132F3BCF8A68169C7ECB852EFD8E1A46C9FEC5A0F469ED'){throw 'Pinned Node download hash mismatch.'}
  }
  $null=Get-DreamSkinValidatedNodeRuntime -Path $nodePath
  $nodeLicense=if($context.Node){Join-Path (Split-Path -Parent $context.Node.Path) LICENSE}else{Join-Path $skillRoot 'assets\NODE-LICENSE.txt'}
  if(-not(Test-Path -LiteralPath $nodeLicense)){throw 'The selected Node runtime license is missing; no installation was committed.'}
  Copy-Item -LiteralPath $nodeLicense -Destination (Join-Path $nodeDir LICENSE)
  & (Join-Path $skillRoot 'scripts\Build-Runtime.ps1') -SourceDirectory (Join-Path $stage '.') -OutputDirectory $stage|Out-Null
  @{product='codex-image-skin/1';version='0.2.0-preview.1';runtimeMode='native-in-place';installed=(Get-Date).ToString('o');engineVersion='1.5.21'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $stage installation.json) -Encoding UTF8
  [IO.Directory]::Move($stage,$ownRoot);$stage=$null
  $script:owned=$true
  $health=Register-SkinTask $context
  @{status='installed-verified';runtimeRoot=$ownRoot;persistence=$health;coldLaunchTested=$false;originalEntryPreserved=$true}
 }finally{
  if($stage -and (Test-Path -LiteralPath $stage) -and $stage.StartsWith($ownRoot+'.install-', [StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $stage -Recurse -Force}
 }
}

if($Action -eq 'Doctor'){
 $app=$null;$node=$null;$appError=$null;$nodeError=$null;$persistence=$null
 try{$app=Get-DreamSkinCodexInstall;$persistence=Get-Persistence $app}catch{$appError=$_.Exception.Message}
 try{$node=Get-NodeRuntime}catch{$nodeError=$_.Exception.Message}
 $osSupported=[Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and [Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess
 $owl=$false;$profileExists=$false
 if($app){
  $owl=Test-Path -LiteralPath (Join-Path (Split-Path -Parent $app.Executable) 'owl-shell-runtime.json')
  $profile=Join-Path $env:LOCALAPPDATA ('Packages\'+$app.PackageFamilyName+'\LocalCache\Roaming\Codex\web\Codex')
  $profileExists=(Test-Path -LiteralPath (Join-Path $profile 'Local State')) -and (Test-Path -LiteralPath (Join-Path $profile 'Default\Preferences'))
 }
 @{status='diagnosed';platform='windows-x64';supported=([bool]$app -and $osSupported -and $owl -and $profileExists);owlRuntime=$owl;existingProfile=$profileExists;codexVersion=$app.Version;runtimeOwned=$owned;engineRoot=$engineRoot;stateRoot=$stateRoot;node=$node;nodeError=$nodeError;appError=$appError;persistence=$persistence;currentSkinChanged=$false}|ConvertTo-Json -Depth 7
 exit 0
}
if($Action -eq 'Validate'){$node=Get-NodeRuntime;$pack=Assert-Theme $ThemeDirectory $node;@{status='validated';themeDirectory=$pack.Directory;result=$pack.Validation}|ConvertTo-Json -Depth 6;exit 0}
if($Action -eq 'Install'){
 $context=[pscustomobject]@{App=(Get-DreamSkinCodexInstall);Node=$null};try{$context.Node=Get-NodeRuntime}catch{if(-not $AllowRuntimeDownload){throw}}
 Install-Runtime $context|ConvertTo-Json -Depth 6;exit 0
}
$context=Get-Context
$persistence=Get-Persistence $context.App
$active=Join-Path $stateRoot active-theme
if($WhatIfPreference -and $Action -in @('Apply','Pause','Resume','Disable')){@{status='planned';action=$Action;stateRoot=$stateRoot;currentSkinChanged=$false}|ConvertTo-Json;exit 0}
if($Action -eq 'Disable'){
 if(-not $owned){throw 'This runtime belongs to another installation; use Pause instead.'}
 $expected='"'+(Join-Path $ownRoot 'ImageSkinLaunchBroker.exe')+'"'
 if((Get-Callback $context.App) -cne $expected){throw 'Callback ownership changed; it was preserved.'}
 [IO.File]::WriteAllText((Join-Path $ownRoot 'original-profile.stop'),'Disabled explicitly')
 Add-Type -Path (Join-Path $ownRoot 'ImageSkinPrelaunch.dll');[ImageSkinPrelaunch]::Unregister($context.App.PackageFullName)
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$task=$service.GetFolder('\').GetTask('CodexImageSkin')
 if(-not(Test-DreamSkinPathEqual $task.Definition.Actions.Item(1).Path (Join-Path $ownRoot 'ImageSkinHost.exe'))){throw 'Task ownership changed; preserved.'};$task.Enabled=$false
 $loading=@($service.GetFolder('\').GetTasks(1)|Where-Object Name -eq 'CodexImageSkinLoading')|Select-Object -First 1
 if($loading){if($loading.Definition.Actions.Count -ne 1 -or -not(Test-DreamSkinPathEqual $loading.Definition.Actions.Item(1).Path (Join-Path $ownRoot 'ImageSkinLoadingHost.exe'))){throw 'Loading task ownership changed; preserved.'};$loading.Enabled=$false}
 @{status='disabled';appClosed=$false}|ConvertTo-Json;exit 0
}
if($Action -eq 'Pause'){
 [IO.File]::WriteAllText((Join-Path $stateRoot paused),'Paused explicitly')
 $live=Get-LiveState $context
 if($live){& $context.Node.Path (Join-Path $engineRoot 'scripts\injector.mjs') --remove --port $live.State.port --browser-id $live.Identity.BrowserId|Out-Null;if($LASTEXITCODE -ne 0){throw 'Pause was saved, but current renderer removal did not complete.'}}
 @{status='paused';backgroundPreserved=$true;appClosed=$false}|ConvertTo-Json;exit 0
}
if($Action -eq 'Status'){
 $live=Get-LiveState $context;$visibility='not-connected';$verification=$null;$injectorAlive=$false
 if($live){
  $v=& $context.Node.Path (Join-Path $engineRoot 'scripts\injector.mjs') --verify --port $live.State.port --browser-id $live.Identity.BrowserId --theme-dir $active --timeout-ms 4000
  $verification=$v|ConvertFrom-Json;$visibility=Get-ImageSkinVerificationState $verification
  $p=if($live.State.injectorPid){Get-Process -Id $live.State.injectorPid -ErrorAction SilentlyContinue}else{$null}
  if($p){$injectorAlive=($p.StartTime.ToUniversalTime().ToString('o') -ceq $live.State.injectorStartedAt)}
 }
 $selected=if(Test-Path -LiteralPath (Join-Path $active theme.json)){Get-Content -LiteralPath (Join-Path $active theme.json) -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}
 @{status='checked';themeId=$selected.id;visibility=$visibility;injectorAlive=$injectorAlive;persistence=$persistence;paused=(Test-Path -LiteralPath (Join-Path $stateRoot paused));coldLaunchTested=$false}|ConvertTo-Json -Depth 7;exit 0
}
if($Action -eq 'Resume'){$ThemeDirectory=$active}
if(-not $persistence.configured){throw 'No verified automatic recovery owner. Theme may be prepared, but persistence must be installed or repaired before Apply.'}
$pack=Assert-Theme $ThemeDirectory $context.Node
[IO.Directory]::CreateDirectory($proofRoot)|Out-Null
$lock=Enter-DreamSkinOperationLock -TimeoutMilliseconds 5000
$backup=$null;$stage=$null;$switched=$false
try{
 if(-not(Test-DreamSkinPathEqual $pack.Directory $active)){
  $stage=Join-Path $stateRoot ('active-theme.preparing-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($stage)|Out-Null
  foreach($leaf in @('theme.json','theme.css',$pack.Theme.image)){Copy-Item -LiteralPath (Join-Path $pack.Directory $leaf) -Destination $stage}
  $null=Assert-Theme $stage $context.Node
  if(Test-Path -LiteralPath $active){$backup=Join-Path $stateRoot ('active-theme.backup-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::Move($active,$backup)}
  [IO.Directory]::Move($stage,$active);$stage=$null;$switched=$true
 }
 if(Test-Path -LiteralPath (Join-Path $stateRoot paused)){Remove-Item -LiteralPath (Join-Path $stateRoot paused)}
}catch{
 if($backup -and -not(Test-Path -LiteralPath $active)){[IO.Directory]::Move($backup,$active)}
 throw
}finally{Exit-DreamSkinOperationLock -Mutex $lock}
try{
 if($owned){Sync-ImageSkinLoading -StateRoot $ownRoot -NodePath $context.Node.Path}
 $live=Get-LiveState $context
 if(-not $live){
  $roots=@(Get-DreamSkinCodexProcesses -Codex $context.App|Where-Object{$_.CommandLine -and $_.CommandLine -notmatch '--type='})
  $status=if($roots.Count){'saved-awaiting-reopen'}else{'saved-awaiting-launch'}
  @{status=$status;themeId=$pack.Theme.id;automaticRecoveryConfigured=$persistence.configured;appClosed=$false;backup=$backup}|ConvertTo-Json;exit 0
 }
 $attached=Invoke-ImageSkinFastInjection $context ([int]$live.State.port) $live.Identity $proofRoot $stateRoot
 @{status='applied';themeId=$pack.Theme.id;visibility=$attached.Visibility;automaticRecoveryConfigured=$persistence.configured;coldLaunchTested=$false;backup=$backup}|ConvertTo-Json
}catch{
 # Preserve the failed candidate for inspection and restore the previous pack.
 if($switched -and $backup){
  $failed=Join-Path $stateRoot ('active-theme.failed-'+[guid]::NewGuid().ToString('N'))
  if(Test-Path $active){[IO.Directory]::Move($active,$failed)};[IO.Directory]::Move($backup,$active)
  try{if($owned){Sync-ImageSkinLoading -StateRoot $ownRoot -NodePath $context.Node.Path};$live=Get-LiveState $context;if($live){$null=Invoke-ImageSkinFastInjection $context ([int]$live.State.port) $live.Identity $proofRoot $stateRoot}}catch{Save-OriginalStatus 'rollback-pending' $_.Exception.Message}
 }
 throw
}
