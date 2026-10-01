# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$Archive='', [string]$SourceRoot='')
$ErrorActionPreference='Stop'
if(-not $SourceRoot){$SourceRoot=Split-Path $PSScriptRoot -Parent}
$SourceRoot=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
$internal=@('AGENTS.md','ARCHITECTURE-REVIEW.md','AUDIT.md','BRANDING.md','ERROR-AUDIT.md','LIMITS-VERIFICATION.md','METHODS.md','MIGRATION.md','NATIVE-VERIFICATION.md','NEXT-TASKS.md','PUBLISHING.md','QUEUE-VERIFICATION.md','QUOTA-RESEARCH.md','RELEASE-NOTES.md','USAGE-METHODS.md','VISUAL-PARITY.md','WORK-QUEUE.md','UI-WRITING.md')
$privatePattern='(?i)(^|/)(memory|outputs|tools|diagnostics|\.codex|\.aws|\.vs|\.vscode|Versions|bin|obj)/|(^|/)(auth\.json|config\.toml|overlay\.json|installation\.json|limits-queue[^/]*\.json|restart-request[^/]*\.json|\.env(?:\.[^/]*)?)$|\.(jsonl|sqlite[^/]*|log|bak(?:-[^/]*)?)$'
function Assert-PublicPath([string]$Path){
 $path=$Path.Replace('\','/').TrimStart('/')
 if($internal -contains [IO.Path]::GetFileName($path) -or $path -match $privatePattern){throw "Private work file in distribution: $path"}
}
function Assert-GuideLinks([string]$Text,[string]$Path,[string[]]$Files){
 foreach($match in [regex]::Matches($Text,'\]\((?<target>[^\s)]+)(?:\s+"[^"]*")?\)|\bsrc="(?<target>[^"]+)"')){
  $target=$match.Groups['target'].Value.Trim('<','>')
  if($target -match '^(?:https?:|mailto:|#)'){continue}
  $target=[Uri]::UnescapeDataString(($target -split '#',2)[0])
  $parent=($Path.Replace('\','/') -replace '[^/]+$','')
  $combined=[IO.Path]::GetFullPath((Join-Path $SourceRoot ($parent+$target)))
  $prefix=$SourceRoot+[IO.Path]::DirectorySeparatorChar
  if(-not $combined.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "Guide link leaves product folder: $Path -> $target"}
  $relative=$combined.Substring($prefix.Length).Replace('\','/')
  if($Files -notcontains $relative){throw "Missing guide link: $Path -> $target"}
 }
 if($Text -match '(?i)C:[\\/]Users[\\/]Yahya|F:[\\/]2026|send_user_message_question_reply'){throw "Private machine or chat text in guide: $Path"}
}
$guides=@('README.md','INSTALL.md','UPDATE-RECOVERY.md','COMPATIBILITY.md','SECURITY.md','CHANGELOG.md','ACKNOWLEDGMENTS.md','docs/USER-GUIDE.md','docs/DATA.md')
if($Archive){
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
 try{
  $files=@();$texts=@{}
  foreach($entry in $zip.Entries){
   $name=$entry.FullName.Replace('\','/')
   if(-not $name.StartsWith('ContextWidget/',[StringComparison]::Ordinal)){throw "Archive folder is incorrect: $name"}
   $relative=$name.Substring('ContextWidget/'.Length)
   if(-not $relative -or $relative.EndsWith('/')){continue}
   if($relative -match '(^|/)\.\.(/|$)' -or $relative.Contains(':')){throw "Archive path is incorrect: $name"}
   Assert-PublicPath $relative
   $files+=$relative
   if($guides -contains $relative){
    $reader=[IO.StreamReader]::new($entry.Open())
    try{$texts[$relative]=$reader.ReadToEnd()}finally{$reader.Dispose()}
   }
  }
  foreach($required in @('Setup.exe','LICENSE','THIRD_PARTY_NOTICES.md','Build/ctc-logo.png')+$guides){
   if($files -notcontains $required){throw "Missing release file: $required"}
  }
  if($files -contains 'ContextTokenCodex.exe'){
   foreach($required in @('native-files.json','DOTNET-LICENSE.txt','DOTNET-THIRD-PARTY-NOTICES.txt')){
    if($files -notcontains $required){throw "Missing runtime notice or manifest: $required"}
   }
  }
  foreach($guide in $guides){Assert-GuideLinks $texts[$guide] $guide $files}
  Write-Output ("PASS Public package: {0} files; user guides and notices included; local work files excluded." -f $files.Count)
 }finally{$zip.Dispose()}
}else{
 $tracked=@()
 if((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $SourceRoot '.git'))){
  $gitRoot=& git -C $SourceRoot rev-parse --show-toplevel 2>$null
  if($LASTEXITCODE -eq 0 -and [IO.Path]::GetFullPath([string]$gitRoot).TrimEnd('\','/') -eq $SourceRoot){
   $tracked=@(& git -C $SourceRoot ls-files)
   foreach($path in $tracked){Assert-PublicPath $path}
   if(@($tracked|Where-Object {$_ -match '\.(exe|zip|pdb)$'}).Count){throw 'Generated binaries are tracked in source.'}
  }
 }
 $files=@(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse | Where-Object FullName -NotMatch '[\\/](dist|\.git|\.packages|bin|obj)[\\/]' | ForEach-Object {$_.FullName.Substring($SourceRoot.Length+1).Replace('\','/')})
 foreach($guide in @($guides+@('CONTRIBUTING.md','RECOVERY.md')+@($tracked|Where-Object {$_ -like '*.md'})|Select-Object -Unique)){
  if($files -notcontains $guide){throw "Missing public guide: $guide"}
  Assert-GuideLinks ([IO.File]::ReadAllText((Join-Path $SourceRoot $guide))) $guide $files
 }
 foreach($name in $internal){
  if(-not ([IO.File]::ReadAllLines((Join-Path $SourceRoot '.gitignore')) -contains ('/'+$name))){throw "Missing local-only ignore rule: $name"}
 }
 Write-Output ("PASS Public source: {0} tracked files checked; guide links and local-only ignore rules checked." -f $tracked.Count)
}
