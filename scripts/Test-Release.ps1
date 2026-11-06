[CmdletBinding()]
param([switch]$SkipWindowTests)
$ErrorActionPreference='Stop'
$env:PSModulePath="$env:WINDIR\System32\WindowsPowerShell\v1.0\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
$repository=Split-Path -Parent $PSScriptRoot
$skill=Join-Path $repository 'skills\codex-image-skin'
$runtime=Join-Path $skill 'assets\runtime'
$case=Join-Path $repository ('.validation\run-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($case)|Out-Null
$checks=New-Object 'Collections.Generic.List[string]'
function Check([bool]$pass,[string]$name){if(-not $pass){throw $name};$checks.Add($name);Write-Host ('PASS '+$name)}
foreach($scope in @('scripts','tests','skills')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $repository $scope) -Recurse -File -Filter '*.ps1'){
  $parseErrors=$null;$tokens=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count){throw ($file.Name+': '+($parseErrors.Message -join '; '))}
 }
}
$checks.Add('PowerShell syntax')
& (Join-Path $skill 'scripts\Build-Runtime.ps1') -OutputDirectory (Join-Path $case bin)|Out-Null
$checks.Add('All native runtime binaries compile')
$manifest=Get-Content -LiteralPath (Join-Path $skill 'assets\engine-files.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($p in $manifest.files.PSObject.Properties){Check ((Get-FileHash -LiteralPath (Join-Path $skill ('assets\engine\'+$p.Name)) -Algorithm SHA256).Hash -ieq $p.Value) ('engine hash: '+$p.Name)}
$node=(Get-Command node.exe -ErrorAction SilentlyContinue).Source
if(-not $node){$candidate=Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\engine\runtime\node\node.exe';if(Test-Path -LiteralPath $candidate){$node=$candidate}}
if(-not $node){throw 'Node 22+ is required for release validation.'}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $skill 'assets') -Recurse -File|Where-Object Extension -in @('.js','.mjs','.cjs')){& $node --check $file.FullName;if($LASTEXITCODE -ne 0){throw ('JavaScript syntax: '+$file.Name)}}
$checks.Add('JavaScript syntax')
$destination=Join-Path $case 'copied-skill'
$copied=& (Join-Path $PSScriptRoot Install-Skill.ps1) -Destination $destination|ConvertFrom-Json
Check ($copied.status -eq 'skill-copied' -and $copied.runtimeInstalled -eq $false) 'Skill copy does not install a runtime'
$saved=(Get-FileHash -LiteralPath (Join-Path $destination SKILL.md)).Hash
$rejected=$false;try{& (Join-Path $PSScriptRoot Install-Skill.ps1) -Destination $destination|Out-Null}catch{$rejected=$true}
Check ($rejected -and (Get-FileHash -LiteralPath (Join-Path $destination SKILL.md)).Hash -eq $saved) 'Existing skill is preserved'
$plan=Join-Path $case whatif-skill
& (Join-Path $PSScriptRoot Install-Skill.ps1) -Destination $plan -WhatIf
Check (-not(Test-Path -LiteralPath $plan)) 'WhatIf does not copy a skill'
Add-Type -AssemblyName System.Drawing
$sampleImagePath=Join-Path $case 'input [sample] $(literal).png'
$image=[Drawing.Bitmap]::new(320,180);$graphics=[Drawing.Graphics]::FromImage($image)
try{$graphics.Clear([Drawing.Color]::SteelBlue);$graphics.FillRectangle([Drawing.Brushes]::Orange,180,0,140,180);$image.Save($sampleImagePath,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$image.Dispose()}
$sourceHash=(Get-FileHash -LiteralPath $sampleImagePath).Hash
foreach($mode in @('light','dark')){
 $prepared=& (Join-Path $skill 'scripts\New-ImageTheme.ps1') -ImagePath $sampleImagePath -Name ('Sample '+$mode) -Appearance $mode -OutputRoot (Join-Path $case library)|ConvertFrom-Json
 Check ($prepared.status -eq 'prepared' -and $prepared.activeSkinChanged -eq $false) ('Prepare '+$mode+' without applying')
 $result=& $node (Join-Path $skill 'assets\engine\scripts\injector.mjs') --check-payload --theme-dir $prepared.themeDirectory|ConvertFrom-Json
 Check ($LASTEXITCODE -eq 0 -and $result.pass) ('Validate '+$mode+' with real engine')
 $theme=Get-Content -LiteralPath (Join-Path $prepared.themeDirectory 'theme.json') -Raw -Encoding UTF8|ConvertFrom-Json
}
Check ((Get-FileHash -LiteralPath $sampleImagePath).Hash -eq $sourceHash) 'Original image preserved'
$bad=Join-Path $case malformed.png;[IO.File]::WriteAllText($bad,'this is not a valid image input')
$rejected=$false;try{& (Join-Path $skill 'scripts\New-ImageTheme.ps1') -ImagePath $bad -OutputRoot (Join-Path $case invalid-library)|Out-Null}catch{$rejected=$true}
Check ($rejected -and -not(Test-Path -LiteralPath (Join-Path $case invalid-library))) 'Malformed input does not commit a theme'
. (Join-Path $skill 'assets\engine\scripts\common-windows.ps1')
. (Join-Path $runtime 'Configure-Loading.ps1')
$native=Join-Path $case native;[IO.Directory]::CreateDirectory($native)|Out-Null
Copy-Item -LiteralPath $prepared.themeDirectory -Destination (Join-Path $native active-theme) -Recurse
@{credit='byDemo';primary='Loading';secondary='Test';enabled=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $native loading-preferences.json) -Encoding UTF8
Sync-ImageSkinLoading -StateRoot $native -NodePath $node
$config=Get-Content -LiteralPath (Join-Path $native loading-config.json) -Raw -Encoding UTF8|ConvertFrom-Json
Check ($config.credit -eq 'byDemo' -and $config.themeId -eq $theme.id -and $config.colors.background -eq $theme.colors.background -and (Test-Path -LiteralPath $config.artPath)) 'Loading picture, palette, text and identity follow selected theme'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$long=Join-Path $case 'long-fixture-directory-name-to-leave-space-for-the-in-place-port';[IO.Directory]::CreateDirectory($long)|Out-Null
$fixture=Join-Path $long ChatGPT.exe
& $compiler /nologo /target:exe /platform:x64 ('/out:'+$fixture) (Join-Path $repository 'tests\EchoFixture.cs');if($LASTEXITCODE -ne 0){throw 'Fixture compile failed'}
& $compiler /nologo /target:exe /platform:x64 ('/out:'+(Join-Path $case 'arguments.exe')) (Join-Path $repository 'tests\TestNativeArguments.cs') (Join-Path $runtime NativeStartupArguments.cs);if($LASTEXITCODE -ne 0){throw 'Argument test compile failed'}
$alias=Join-Path $case alias;New-Item -ItemType Junction -Path $alias -Target $long|Out-Null
& (Join-Path $case arguments.exe) $fixture (Join-Path $alias ChatGPT.exe)
if($LASTEXITCODE -ne 0){throw 'In-place argument regression failed'}
$checks.Add('In-place arguments, protocol preservation and bounded refusal')
if(-not $SkipWindowTests){
 foreach($test in @('Test-Native-Cover','Test-Native-Handover')){
  $binary=Join-Path $native ($test+'.exe')
  & $compiler /nologo /target:exe /platform:x64 /r:System.Web.Extensions.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll ('/out:'+$binary) (Join-Path $repository ('tests\'+$test+'.cs')) (Join-Path $runtime ImageSkinLoadingCover.cs)
  if($LASTEXITCODE -ne 0){throw ($test+' compile failed')}
  & $binary
  if($LASTEXITCODE -ne 0){throw ($test+' failed')}
  $checks.Add($test)
 }
}
$forbidden='(?i)\b[A-Z]:[\\/](?:[^\\/\s"<>]+[\\/])+'
foreach($scope in @('skills','scripts','tests','docs')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $repository $scope) -Recurse -File|Where-Object Extension -in @('.ps1','.cs','.js','.mjs','.cjs','.json','.md','.yaml','.yml')){
  Check (-not [regex]::IsMatch([IO.File]::ReadAllText($file.FullName),$forbidden)) ('portable source: '+$file.Name)
 }
}
$proof=@{pass=$true;checked=(Get-Date).ToString('o');checks=@($checks);windowTestsRun=(-not $SkipWindowTests);cleanInstallTested=$false;currentCodexChanged=$false;artifactDirectory=$case}
$proof|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $repository '.validation\latest.json') -Encoding UTF8
Write-Host ('PASS release component checks; '+$checks.Count+' checks')
