function Sync-ImageSkinLoading([string]$StateRoot,[string]$NodePath){
 $themeFile=Join-Path $StateRoot 'active-theme\theme.json'
 if(-not(Test-Path -LiteralPath $themeFile)){return}
 $theme=Get-Content -LiteralPath $themeFile -Raw -Encoding UTF8|ConvertFrom-Json
 $preferences=Join-Path $StateRoot 'loading-preferences.json'
 $settings=@{}
 if(Test-Path -LiteralPath $preferences){
  if((Get-Item -LiteralPath $preferences).Length -gt 16384){throw 'Loading preferences are oversized.'}
  $raw=Get-Content -LiteralPath $preferences -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($p in $raw.PSObject.Properties){$settings[$p.Name]=$p.Value}
 }
 $config=@{schemaVersion=1;enabled=$true;loadingMode='native-overlay';nodePath=$NodePath;nodeSha256=(Get-FileHash -LiteralPath $NodePath -Algorithm SHA256).Hash;themeId=$theme.id;artPath=(Join-Path (Join-Path $StateRoot 'active-theme') $theme.image);pausePath=(Join-Path $StateRoot paused);capturePreview=$false;focusX=.5;focusY=.5;colors=$theme.colors;eyebrow='';primary='正在准备界面';secondary='';hintPrimary='完成后将自动进入 Codex';hintSecondary='';credit=''}
 if($theme.art){if($null -ne $theme.art.focusX){$config.focusX=$theme.art.focusX};if($null -ne $theme.art.focusY){$config.focusY=$theme.art.focusY}}
 foreach($key in @('eyebrow','primary','secondary','hintPrimary','hintSecondary','credit')){
  if($settings.ContainsKey($key)){
   $value=$settings[$key]
   if($value -isnot [string] -or $value.Length -gt 120 -or $value -match '[\x00-\x1F\x7F]'){throw ('Invalid loading text: '+$key)}
   $config[$key]=$value
  }
 }
 if($settings.ContainsKey('enabled')){if($settings.enabled -isnot [bool]){throw 'Loading enabled must be a boolean.'};$config.enabled=$settings.enabled}
 Write-DreamSkinUtf8FileAtomically -Path (Join-Path $StateRoot 'loading-config.json') -Content ($config|ConvertTo-Json -Depth 6)
}
