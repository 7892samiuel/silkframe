function Get-OriginalRootKey($process){
 "$($process.ProcessId)/$($process.CreationDate.ToUniversalTime().Ticks)"
}
function Get-OriginalRootPort($process){
 if($process.CommandLine -match '--remote-debugging-port="?(\d+)'){
  $candidate=[int]$Matches[1]
  if($candidate -ge 1024 -and $candidate -le 65535){return $candidate}
 }
 return 0
}
function Test-OriginalRootNeedsHandling($process,$handled,$attempted,$retries,[datetime]$now){
 $key=Get-OriginalRootKey $process
 if($process.CommandLine -match '--remote-debugging'){
  if(-not $handled.ContainsKey($key)){return $true}
  return ($retries -and $retries.ContainsKey($key) -and $retries[$key].Remaining -gt 0 -and $now -ge $retries[$key].Due)
 }
 return (-not $handled.ContainsKey($key) -and -not $attempted.ContainsKey($key))
}
function Resolve-OriginalConnection($context,$roots){
 $debug=@($roots|Where-Object{$_.CommandLine -match '--remote-debugging'})
 if($debug.Count -gt 0){
  if($debug.Count -ne 1){throw 'Multiple debug browsers were preserved; no automatic restart.'}
  $port=Get-OriginalRootPort $debug[0]
  if($port -eq 0){throw 'Unsupported debug transport; existing browser preserved.'}
  $identity=Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $context.App
  if(-not $identity){throw 'The existing debug browser is not ready; it was not restarted.'}
  return [pscustomobject]@{Port=$port;Identity=$identity;Reuse=$true}
 }
 throw 'Ordinary activation is preserved. Waiting for the pre-window theme browser; no restart is allowed.'
}
function Read-OriginalAttempts([string]$path){
 $entries=@{}
 if(Test-Path -LiteralPath $path){
  $file=Get-Item -LiteralPath $path
  if($file.Length -gt 131072){throw 'Attempt ledger is oversized; current app preserved.'}
  $saved=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  if($saved.schemaVersion -ne 1){throw 'Unknown attempt ledger format; current app preserved.'}
  foreach($entry in @($saved.entries)){
   if($entry.key -notmatch '^\d+/\d+$'){throw 'Invalid attempt identity; current app preserved.'}
   $entries[$entry.key]=$entry.updated
  }
 }
 return $entries
}
function Save-OriginalAttempts([string]$path,$ledger,$processes){
 foreach($process in $processes){$ledger[(Get-OriginalRootKey $process)]=[DateTime]::UtcNow.ToString('o')}
 $entries=@($ledger.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 256|ForEach-Object{[pscustomobject]@{key=$_.Key;updated=$_.Value}})
 $json=@{schemaVersion=1;entries=$entries}|ConvertTo-Json -Depth 4
 Write-DreamSkinUtf8FileAtomically -Path $path -Content ($json+"`r`n")
}
