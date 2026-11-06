[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$Destination)
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repository 'skills\codex-image-skin'
if(-not $Destination){$Destination=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agents\skills\codex-image-skin'}
$target=[IO.Path]::GetFullPath($Destination)
if($target.StartsWith($source.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination cannot be inside the source skill.'}
if(Test-Path -LiteralPath $target){throw 'The destination already exists and was preserved. Choose another destination or remove the old skill explicitly.'}
if(-not $PSCmdlet.ShouldProcess($target,'Copy codex-image-skin skill (no runtime installation)')){return}
$parent=Split-Path -Parent $target;[IO.Directory]::CreateDirectory($parent)|Out-Null
$stage=$target+'.install-'+[guid]::NewGuid().ToString('N')
try{
 [IO.Directory]::CreateDirectory($stage)|Out-Null
 foreach($entry in Get-ChildItem -LiteralPath $source -Force){Copy-Item -LiteralPath $entry.FullName -Destination $stage -Recurse}
 [IO.Directory]::Move($stage,$target);$stage=$null
 @{status='skill-copied';path=$target;runtimeInstalled=$false}|ConvertTo-Json
}finally{
 if($stage){$resolved=[IO.Path]::GetFullPath($stage);if($resolved.StartsWith($target+'.install-',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetDirectoryName($resolved) -eq $parent -and (Test-Path -LiteralPath $resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}}
}
