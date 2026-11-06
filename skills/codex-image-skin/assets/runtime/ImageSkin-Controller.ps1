[CmdletBinding()]
param([switch]$InspectOnly,[switch]$ApplyOnce,[switch]$Watch,[int]$DelaySeconds=0)
$env:PSModulePath="$env:WINDIR\System32\WindowsPowerShell\v1.0\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
$ErrorActionPreference='Stop'
$taskRoot=$PSScriptRoot
$engineScripts=Join-Path $env:LOCALAPPDATA 'CodexImageSkin\engine\scripts'
. (Join-Path $engineScripts 'common-windows.ps1')
. (Join-Path $taskRoot 'ImageSkin-Injector.ps1')
. (Join-Path $taskRoot 'ImageSkin-Connection.ps1')
. (Join-Path $taskRoot 'Register-ImageSkin.ps1')
$statusPath=Join-Path $taskRoot 'original-profile-status.json'
$stopPath=Join-Path $taskRoot 'original-profile.stop'
function Save-OriginalStatus([string]$state,[string]$detail){
 @{state=$state;detail=$detail;pid=$PID;updated=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $statusPath -Encoding UTF8
 [IO.File]::AppendAllText((Join-Path $taskRoot 'original-profile-events.log'),((Get-Date).ToString('o')+' '+$state+' '+$detail+[Environment]::NewLine))
}
function Get-OriginalContext {
 $app=Get-DreamSkinCodexInstall
 $logical=Join-Path $env:APPDATA 'Codex\web\Codex'
 $physical=Join-Path $env:LOCALAPPDATA ('Packages\'+$app.PackageFamilyName+'\LocalCache\Roaming\Codex\web\Codex')
 if(-not(Test-Path -LiteralPath (Join-Path (Split-Path -Parent $app.Executable) 'owl-shell-runtime.json'))){throw 'This adapter requires the verified Owl runtime.'}
 # Only inspect the physical AppData view. Never create a second profile.
 if(-not(Test-Path -LiteralPath (Join-Path $physical 'Local State')) -or -not(Test-Path -LiteralPath (Join-Path $physical 'Default\Preferences'))){throw 'Existing official Store profile was not found.'}
 $node=Get-DreamSkinValidatedNodeRuntime -Path (Join-Path $taskRoot 'engine\runtime\node\node.exe')
 [pscustomobject]@{App=$app;LogicalProfile=$logical;PhysicalProfile=$physical;ProfileMode='native-default';Node=$node}
}
function Get-OfficialRoots($context){
 @(Get-DreamSkinCodexProcesses -Codex $context.App|Where-Object{$_.CommandLine -and $_.CommandLine -notmatch '--type='})
}
function Assert-OriginalRoots($roots,$context){
 foreach($p in $roots){
  if($p.CommandLine -match 'CodexDreamSkin[\\/]cdp-profile'){throw 'An old isolated theme instance is still running; it was preserved.'}
  if($p.CommandLine -match '--user-data-dir(?:=|\s)'){throw 'An explicit profile was preserved; this runtime uses the native default profile.'}

 }
}
function Invoke-OriginalApply($context) {
 $cycleClock=[Diagnostics.Stopwatch]::StartNew()
 if(-not $context){$context=Get-OriginalContext}
 $roots=@(Get-OfficialRoots $context)
 if($roots.Count -eq 0){Save-OriginalStatus 'idle' 'Codex is absent; no app was launched.';return}
 Assert-OriginalRoots $roots $context
 $connection=Resolve-OriginalConnection $context $roots
 $port=$connection.Port
 $identity=$connection.Identity
 if(-not $connection.Reuse){
  throw 'This launch has no prepared theme channel; app preserved without closing or restarting.'
 }
 Save-OriginalStatus 'injecting' 'Applying ImageSkin directly; no generic app launcher or repeated verification.'
 $attachment=Invoke-ImageSkinFastInjection $context $port $identity $taskRoot
 $roots=@(Get-OfficialRoots $context)
 Assert-OriginalRoots $roots $context
 $native=Get-Content -LiteralPath (Join-Path $taskRoot 'native-startup-config.json') -Raw|ConvertFrom-Json
 $debugRoots=@($roots|Where-Object{(Get-OriginalRootPort $_) -eq $port -and $_.CommandLine.StartsWith(('"'+$native.argumentAlias+'" '),[StringComparison]::OrdinalIgnoreCase)})
 if($debugRoots.Count -ne 1){throw 'Expected exactly one original-profile debugging browser; automatic handling paused.'}
 # Process count is not native window count. Keep complete process evidence;
 # all profiles must be the original profile and only one CDP browser may exist.
 $cycleClock.Stop()
 @{profileMode='native-default';startupMode='direct-injector';port=$port;codexVersion=$context.App.Version;visibility=$attachment.Visibility;visibleConfirmed=($attachment.Visibility -eq 'visible');totalApplyMs=[Math]::Round($cycleClock.Elapsed.TotalMilliseconds);logicalProfile=$null;physicalProfile=$null;rootCount=$roots.Count;debugRootCount=$debugRoots.Count;roots=@($roots|Select-Object ProcessId,ParentProcessId,CreationDate,CommandLine);checked=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskRoot 'original-profile-proof.json') -Encoding UTF8
 if($attachment.Visibility -eq 'visible'){Save-OriginalStatus 'verified' 'Original existing profile and exactly one debug browser; visible ImageSkin renderer verified.'}
 else{Save-OriginalStatus 'applied-hidden' 'ImageSkin installed in the original main window; the window is hidden/minimized, so no visible-success claim or further injection retry.'}
}
$mutex=[Threading.Mutex]::new($false,'Local\CodexImageSkinProfileController')
$held=$false
$transcribing=$false
try{
 $held=$mutex.WaitOne(0)
 if(-not $held){exit 0}
 $context=Get-OriginalContext
 if($InspectOnly){
  $roots=Get-OfficialRoots $context
  Assert-OriginalRoots $roots $context
  @{mode='read-only';originalProfileExists=$true;logicalProfile=$context.LogicalProfile;physicalProfile=$context.PhysicalProfile;roots=@($roots|Select-Object ProcessId,CommandLine);wouldCreateProfile=$false}|ConvertTo-Json -Depth 4
  exit 0
 }
 if(-not $ApplyOnce -and -not $Watch){throw 'Choose InspectOnly, ApplyOnce or Watch.'}
 if(Test-Path -LiteralPath $stopPath){Save-OriginalStatus 'disabled' 'Original-profile controller disabled.';exit 0}
 Start-Transcript -LiteralPath (Join-Path $taskRoot 'original-profile-controller.log') -Append|Out-Null
 $transcribing=$true
 if($ApplyOnce -and $DelaySeconds -gt 0){Start-Sleep -Seconds ([Math]::Min($DelaySeconds,30))}
 if($ApplyOnce){Invoke-OriginalApply $context;exit 0}
 Register-ImageSkinPrelaunch $context
 Save-OriginalStatus 'watching' 'Watching the original profile; no separate app entry or profile.'
 $ledgerPath=Join-Path $taskRoot 'original-profile-attempts.json'
 $attempted=Read-OriginalAttempts $ledgerPath
 $handled=@{};foreach($key in $attempted.Keys){$handled[$key]=$true}
 $attachRetries=@{}
 $discovered=@{}
 $nextDiscovery=[DateTime]::UtcNow.AddSeconds(30)
 while(-not(Test-Path -LiteralPath $stopPath)){
  $candidates=@(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -notmatch '--type='})
  $changed=$false
  foreach($candidate in $candidates){
   $key=Get-OriginalRootKey $candidate
   if(-not $discovered.ContainsKey($key)){
    $discovered[$key]=$true
    $candidatePath=Get-DreamSkinProcessExecutablePath -ProcessInfo $candidate
    if($candidatePath -match '\\WindowsApps\\OpenAI\.Codex_[^\\]+__2p2nqsd0c76g0\\app\\ChatGPT\.exe$' -and -not(Test-DreamSkinPathEqual -Left $candidatePath -Right $context.App.Executable)){$changed=$true}
   }
  }
  if($changed -or [DateTime]::UtcNow -ge $nextDiscovery){
   try{$previousPackage=$context.App.PackageFullName;$context=Get-OriginalContext;if($previousPackage -ne $context.App.PackageFullName){Register-ImageSkinPrelaunch $context};$nextDiscovery=[DateTime]::UtcNow.AddSeconds(30)}
   catch{Save-OriginalStatus 'waiting-update' ('Package discovery is temporarily unavailable; app preserved: '+$_.Exception.Message);$nextDiscovery=[DateTime]::UtcNow.AddSeconds(4);Start-Sleep -Milliseconds 700;continue}
  }
  $roots=@(Get-OfficialRoots $context)
  if($roots.Count -eq 0){$handled=@{};$attachRetries=@{}}
  $newRoots=@($roots|Where-Object{Test-OriginalRootNeedsHandling $_ $handled $attempted $attachRetries ([DateTime]::UtcNow)})
  if($newRoots.Count -gt 0){
   Start-Sleep -Milliseconds 300
   if(Test-Path -LiteralPath $stopPath){break}
   $ordinary=@($newRoots|Where-Object{$_.CommandLine -notmatch '--remote-debugging'})
   # Persist before any handoff, so a host restart cannot close the same
   # ordinary launch again. Debug browsers can be reattached without closing.
   Save-OriginalAttempts $ledgerPath $attempted $ordinary
   foreach($p in $newRoots){
    $key=Get-OriginalRootKey $p
    $handled[$key]=$true
    if($p.CommandLine -match '--remote-debugging'){
     if($attachRetries.ContainsKey($key)){$attachRetries[$key].Remaining--}
     else{$attachRetries[$key]=[pscustomobject]@{Remaining=2;Due=[DateTime]::UtcNow}}
    }
   }
   try{Invoke-OriginalApply $context;foreach($p in (Get-OfficialRoots $context)){$attachRetries.Remove((Get-OriginalRootKey $p))}}
   catch{
    $remaining=@(Get-OfficialRoots $context)
    Save-OriginalAttempts $ledgerPath $attempted @($remaining|Where-Object{$_.CommandLine -notmatch '--remote-debugging'})
    $canRetry=$false
    foreach($p in @($remaining|Where-Object{(Get-OriginalRootPort $_) -gt 0})){
     $key=Get-OriginalRootKey $p
     if(-not $attachRetries.ContainsKey($key)){$attachRetries[$key]=[pscustomobject]@{Remaining=2;Due=[DateTime]::UtcNow.AddSeconds(1)}}
     else{$attachRetries[$key].Due=[DateTime]::UtcNow.AddSeconds(1)}
     if($attachRetries[$key].Remaining -gt 0){$canRetry=$true}
    }
    if($canRetry){Save-OriginalStatus 'retrying-injection' ('Only skin attachment will retry on the existing debug browser; no app restart: '+$_.Exception.Message)}
    else{Save-OriginalStatus 'deferred' ('This launch was preserved after an error; watcher remains alive for a fresh launch: '+$_.Exception.Message)}
   }
   foreach($p in (Get-OfficialRoots $context)){$handled[(Get-OriginalRootKey $p)]=$true}
  }
  Start-Sleep -Milliseconds 700
 }
}catch{
 Save-OriginalStatus 'failed' $_.Exception.Message
 # A fatal controller error is reported to the scheduler. The explicit stop
 # flag belongs to the user's Disable command, not transient runtime errors.
 Write-Error $_
 exit 1
}finally{if($transcribing){Stop-Transcript|Out-Null};if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
