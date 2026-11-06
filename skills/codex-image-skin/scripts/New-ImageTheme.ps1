[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ImagePath,[string]$Name,
 [ValidateSet('auto','light','dark')][string]$Appearance='auto',
 [ValidateRange(0,1)][double]$FocusX=0.72,[ValidateRange(0,1)][double]$FocusY=0.5,
 [string]$OutputRoot=(Join-Path $env:LOCALAPPDATA 'CodexImageSkinLibrary')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
function Mix-Color($a,$b,[double]$amount){[Drawing.Color]::FromArgb([int]($a.R*(1-$amount)+$b.R*$amount),[int]($a.G*(1-$amount)+$b.G*$amount),[int]($a.B*(1-$amount)+$b.B*$amount))}
function Hex-Color($c){'#{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B}
function Rgba-Color($c,[string]$alpha){'rgba({0}, {1}, {2}, {3})' -f $c.R,$c.G,$c.B,$alpha}
$inputFile=Get-Item -LiteralPath $ImagePath
if($inputFile.PSIsContainer -or ($inputFile.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Supply an ordinary local image file.'}
if($inputFile.Length -gt 32MB -or $inputFile.Length -lt 16){throw 'Image must be between 16 bytes and 32 MiB.'}
if(-not $Name){$Name=[IO.Path]::GetFileNameWithoutExtension($inputFile.Name)}
$Name=$Name.Trim();if($Name.Length -gt 80){$Name=$Name.Substring(0,80)}
if(-not $Name -or $Name -match '[\x00-\x1F\x7F]'){throw 'Theme name must be nonempty ordinary text.'}
$bytes=[IO.File]::ReadAllBytes($inputFile.FullName);$memory=[IO.MemoryStream]::new($bytes,$false)
$source=$null;$bitmap=$null;$stage=$null
try {
 $source=[Drawing.Image]::FromStream($memory,$true,$true)
 if($source.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid -and $source.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Jpeg.Guid){throw 'This builder accepts PNG/JPEG. Convert other formats locally before packaging.'}
 if([long]$source.Width*$source.Height -gt 40000000 -or $source.Width -lt 32 -or $source.Height -lt 32){throw 'Image dimensions are unsupported (minimum 32 px, maximum 40 megapixels).'}
 if($source.PropertyIdList -contains 274){
  $orientation=[BitConverter]::ToUInt16($source.GetPropertyItem(274).Value,0)
  $rotations=@{2='RotateNoneFlipX';3='Rotate180FlipNone';4='Rotate180FlipX';5='Rotate90FlipX';6='Rotate90FlipNone';7='Rotate270FlipX';8='Rotate270FlipNone'}
  if($rotations.ContainsKey([int]$orientation)){$source.RotateFlip([Enum]::Parse([Drawing.RotateFlipType],$rotations[[int]$orientation]))}
 }
 $thumb=[Drawing.Bitmap]::new(48,48);$g=[Drawing.Graphics]::FromImage($thumb)
 try{$g.DrawImage($source,0,0,48,48)}finally{$g.Dispose()}
 $red=0L;$green=0L;$blue=0L;$count=0;$best=-1.0;$accent=[Drawing.Color]::FromArgb(78,111,155)
 try{for($y=0;$y -lt 48;$y++){for($x=0;$x -lt 48;$x++){
  $c=$thumb.GetPixel($x,$y);if($c.A -lt 128){continue};$red+=$c.R;$green+=$c.G;$blue+=$c.B;$count++
  $score=$c.GetSaturation()*(1-[Math]::Abs($c.GetBrightness()-0.5));if($score -gt $best){$best=$score;$accent=$c}
 }}}finally{$thumb.Dispose()}
 $mean=if($count -gt 0){[Drawing.Color]::FromArgb([int]($red/$count),[int]($green/$count),[int]($blue/$count))}else{[Drawing.Color]::FromArgb(128,128,128)}
 if($Appearance -eq 'auto'){$Appearance=if((0.2126*$mean.R+0.7152*$mean.G+0.0722*$mean.B) -ge 118){'light'}else{'dark'}}
 if($Appearance -eq 'light'){
  $background=Mix-Color $mean ([Drawing.Color]::White) 0.91;$panel=Mix-Color $mean ([Drawing.Color]::White) 0.96
  $panelAlt=Mix-Color $mean ([Drawing.Color]::White) 0.84;$accent=Mix-Color $accent ([Drawing.Color]::Black) 0.52
  $text=[Drawing.Color]::FromArgb(32,35,43);$muted=[Drawing.Color]::FromArgb(87,91,101);$line=Mix-Color $mean ([Drawing.Color]::White) 0.62
 }else{
  $background=Mix-Color $mean ([Drawing.Color]::Black) 0.87;$panel=Mix-Color $mean ([Drawing.Color]::Black) 0.82
  $panelAlt=Mix-Color $mean ([Drawing.Color]::Black) 0.73;$accent=Mix-Color $accent ([Drawing.Color]::White) 0.58
  $text=[Drawing.Color]::FromArgb(240,242,247);$muted=[Drawing.Color]::FromArgb(190,196,208);$line=Mix-Color $mean ([Drawing.Color]::Black) 0.48
 }
 $hasher=[Security.Cryptography.SHA256]::Create()
 try{
  $sourceHash=([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
  $identity=$sourceHash+'|'+$Name+'|'+$Appearance+'|'+$FocusX.ToString([Globalization.CultureInfo]::InvariantCulture)+'|'+$FocusY.ToString([Globalization.CultureInfo]::InvariantCulture)
  $id='image-'+([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','').Substring(0,16).ToLowerInvariant()
 }finally{$hasher.Dispose()}
 $root=[IO.Path]::GetFullPath($OutputRoot)
 if(Test-Path -LiteralPath $root){if((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Output library cannot be a reparse point.'}}
 [IO.Directory]::CreateDirectory($root)|Out-Null;$destination=Join-Path $root $id
 if(Test-Path -LiteralPath $destination){throw 'This exact image/configuration is already saved. Validate and reuse: '+$destination}
 $stage=Join-Path $root ('.preparing-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($stage)|Out-Null
 $ratio=[Math]::Min(1.0,2560.0/[Math]::Max($source.Width,$source.Height))
 $width=[Math]::Max(32,[int]($source.Width*$ratio));$height=[Math]::Max(32,[int]($source.Height*$ratio));$imageFile=Join-Path $stage 'background.png'
 for($attempt=0;$attempt -lt 8;$attempt++){
  $bitmap=[Drawing.Bitmap]::new($width,$height,[Drawing.Imaging.PixelFormat]::Format32bppArgb);$g=[Drawing.Graphics]::FromImage($bitmap)
  try{$g.CompositingMode=[Drawing.Drawing2D.CompositingMode]::SourceCopy;$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic;$g.DrawImage($source,0,0,$width,$height)}finally{$g.Dispose()}
  $bitmap.Save($imageFile,[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose();$bitmap=$null
  if((Get-Item -LiteralPath $imageFile).Length -le 10MB){break};$width=[Math]::Max(32,[int]($width*0.82));$height=[Math]::Max(32,[int]($height*0.82))
 }
 if((Get-Item -LiteralPath $imageFile).Length -gt 10MB){throw 'Prepared image is still over the 10 MiB limit.'}
 $theme=[ordered]@{schemaVersion=1;id=$id;name=$Name;image='background.png';appearance=$Appearance;art=@{focusX=$FocusX;focusY=$FocusY;safeArea='left';taskMode='ambient'};colors=[ordered]@{background=(Hex-Color $background);panel=(Hex-Color $panel);panelAlt=(Hex-Color $panelAlt);accent=(Hex-Color $accent);accentAlt=(Hex-Color $accent);secondary=(Hex-Color $accent);highlight=(Hex-Color $accent);text=(Hex-Color $text);muted=(Hex-Color $muted);line=(Hex-Color $line)}}
 $css=@"
[data-ds-part="root"] { color: $(Hex-Color $text); }
[data-ds-part="sidebar"] { background-color: $(Rgba-Color $panel '0.9'); border-right-color: $(Hex-Color $line); border-right-width: 1px; border-right-style: solid; }
[data-ds-part="header"] { background-color: $(Rgba-Color $panel '0.82'); border-bottom-color: $(Hex-Color $line); border-bottom-width: 1px; border-bottom-style: solid; }
[data-ds-part="composer"] { background-color: $(Rgba-Color $panel '0.96'); color: $(Hex-Color $text); border-color: $(Hex-Color $line); border-width: 1px; border-style: solid; border-radius: 16px; }
[data-ds-part="dialog"] { background-color: $(Hex-Color $panel); color: $(Hex-Color $text); border-color: $(Hex-Color $line); border-radius: 14px; }
"@
 [IO.File]::WriteAllText((Join-Path $stage 'theme.json'),($theme|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText((Join-Path $stage 'theme.css'),$css,[Text.UTF8Encoding]::new($false))
 [IO.Directory]::Move($stage,$destination);$stage=$null
 @{status='prepared';themeId=$id;themeDirectory=$destination;appearance=$Appearance;width=$width;height=$height;sourceSha256=$sourceHash;sourceCopied=$true;activeSkinChanged=$false}|ConvertTo-Json -Compress
}finally{
 if($bitmap){$bitmap.Dispose()};if($source){$source.Dispose()};$memory.Dispose()
 if($stage -and (Test-Path -LiteralPath $stage)){
  if([IO.Path]::GetFileName($stage) -match '^\.preparing-[a-f0-9]{32}$' -and [IO.Path]::GetDirectoryName($stage) -eq $root){Remove-Item -LiteralPath $stage -Recurse -Force}
 }
}
