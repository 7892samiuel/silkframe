# Uses the installed engine's validator, renderer, identity checks and state
# format. This path never launches, closes or restarts Codex.
function Get-ImageSkinVerificationState($verification){
 $targets=@($verification.targets)
 if($targets.Count -eq 0){return 'invalid'}
 $visible=0
 foreach($target in $targets){
  if($target.error -or -not $target.result){return 'invalid'}
  $r=$target.result
  if($r.pass -eq $true){$visible++;continue}
  # A fully installed but minimized/hidden main page is pending visibility,
  # not an injection failure. Preserve the official visible-pass distinction.
  $sameTheme=$r.themeId -and $r.themeId -ceq $r.expectedThemeId -and $r.revision -and $r.revision -ceq $r.expectedRevision -and $r.version -ceq $r.expectedVersion
  $hiddenReady=$r.installed -eq $true -and $r.stylePresent -eq $true -and $r.documentHidden -eq $true -and $r.documentVisibility -ceq 'hidden' -and $r.readiness.structurePass -eq $true -and $r.readiness.viewportPass -eq $true -and $r.readiness.windowPass -eq $true -and $r.homeComposerPass -eq $true -and $r.businessClassPollution -eq 0
  if(-not $sameTheme -or -not $hiddenReady){return 'invalid'}
 }
 if($visible -gt 0){return 'visible'}
 return 'installed-hidden'
}
function Wait-ImageSkinExpectedBrowser($context,[int]$port,$expected,[int]$TimeoutMilliseconds=8000){
 $deadline=[DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
 $reported=$false
 do{
  $latest=Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $context.App
  if($latest){
   if($latest.BrowserId -cne $expected.BrowserId){throw ('Browser identity actually changed from '+$expected.BrowserId+' to '+$latest.BrowserId+'; no injection or app restart.')}
   return $latest
  }
  if(-not $reported){Save-OriginalStatus 'waiting-cdp' 'The endpoint or page is temporarily unavailable; waiting without restarting the app.';$reported=$true}
  if([DateTime]::UtcNow -ge $deadline){break}
  Start-Sleep -Milliseconds 150
 }while([DateTime]::UtcNow -lt $deadline)
 throw 'The expected browser did not become ready before the deadline; app preserved.'
}
function Invoke-ImageSkinFastInjection($context,[int]$port,$identity,[ValidateNotNullOrEmpty()][string]$ArtifactRoot,[string]$StateRoot=(Join-Path $env:LOCALAPPDATA 'CodexImageSkin')){
 $clock=[Diagnostics.Stopwatch]::StartNew()
 $scripts=Join-Path $StateRoot 'engine\scripts'
 $statePath=Join-Path $stateRoot 'state.json'
 $theme=Join-Path $stateRoot 'active-theme'
 $injector=Join-Path $scripts 'injector.mjs'
 $pause=Join-Path $stateRoot 'paused'
 if(Test-Path -LiteralPath $pause){throw 'The theme was explicitly paused; no automatic override.'}
 $operation=Enter-DreamSkinOperationLock -TimeoutMilliseconds 5000
 try{
  $null=Wait-ImageSkinExpectedBrowser $context $port $identity
  $previous=Read-DreamSkinState -Path $statePath
  if(-not(Stop-DreamSkinRecordedInjector -State $previous)){throw 'Previous injector identity could not be retired safely.'}
  $args=@((ConvertTo-DreamSkinProcessArgument -Value $injector),'--watch','--port',"$port",'--browser-id',$identity.BrowserId,'--theme-dir',(ConvertTo-DreamSkinProcessArgument -Value $theme),'--pause-file',(ConvertTo-DreamSkinProcessArgument -Value $pause))
  $daemon=Start-Process -FilePath $context.Node.Path -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $ArtifactRoot ('fast-injector-'+$identity.BrowserId+'.log')) -RedirectStandardError (Join-Path $ArtifactRoot ('fast-injector-'+$identity.BrowserId+'-error.log'))
  $started=Get-DreamSkinProcessStartedAt -ProcessId $daemon.Id
  if(-not $started -or $daemon.HasExited){throw 'The direct injector did not remain active; app preserved.'}
  $saved=[pscustomobject]@{
   schemaVersion=3;platform='windows';port=$port
   injectorPid=$daemon.Id;injectorStartedAt=$started;injectorPath=$injector
   nodePath=$context.Node.Path;nodeVersion=$context.Node.Version
   codexExe=$context.App.Executable;codexPackageRoot=$context.App.PackageRoot
   codexPackageFullName=$context.App.PackageFullName;codexPackageFamilyName=$context.App.PackageFamilyName
   codexVersion=$context.App.Version;browserId=$identity.BrowserId
   profileMode=$context.ProfileMode;profilePath=$(if($context.ProfileMode -eq 'native-default'){$null}else{$context.LogicalProfile});themeDir=$theme;pauseFile=$pause
   createdAt=[DateTime]::UtcNow.ToString('o')
  }
  Write-DreamSkinState -Path $statePath -State $saved
  Save-OriginalStatus 'injector-running' ('Direct theme watcher started after '+[Math]::Round($clock.Elapsed.TotalMilliseconds)+' ms; no generic launcher.')
  $verifyPath=Join-Path $ArtifactRoot 'fast-visible-verification.json'
  & $context.Node.Path $injector --verify --port "$port" --browser-id $identity.BrowserId --theme-dir $theme --timeout-ms 12000 --screenshot (Join-Path $ArtifactRoot 'original-profile-live.png') *> $verifyPath
  $exitCode=$LASTEXITCODE
  $verified=Get-Content -LiteralPath $verifyPath -Raw|ConvertFrom-Json
  $visibility=Get-ImageSkinVerificationState $verified
  if($visibility -eq 'invalid' -or ($exitCode -ne 0 -and $exitCode -ne 2)){throw 'Direct visible verification did not pass. The current app and injector were left running; no restart.'}
  $clock.Stop()
  @{injectionStageMs=[Math]::Round($clock.Elapsed.TotalMilliseconds);visibility=$visibility;browserId=$identity.BrowserId;injectorPid=$daemon.Id;checked=[DateTime]::UtcNow.ToString('o');verificationPass=($visibility -eq 'visible');genericLauncherCalled=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $ArtifactRoot 'fast-injection-timing.json') -Encoding UTF8
  if($visibility -eq 'visible'){Save-OriginalStatus 'skin-visible' ('Visible ImageSkin skin verified after '+[Math]::Round($clock.Elapsed.TotalMilliseconds)+' ms of the direct injection stage.')}
  else{Save-OriginalStatus 'applied-hidden' 'ImageSkin styles are installed and structurally valid; the main window is minimized/hidden. Waiting for visibility, without reapplying or restarting.'}
  [pscustomobject]@{Visibility=$visibility;Milliseconds=[Math]::Round($clock.Elapsed.TotalMilliseconds)}
 }finally{Exit-DreamSkinOperationLock -Mutex $operation}
}
