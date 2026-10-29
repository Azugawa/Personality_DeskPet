param([string]$Version)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
$out=Join-Path $repo 'build/installer'
$stream=[IO.File]::OpenRead((Join-Path $repo 'build/windows/DeskPet.pck'))
$chunks=@()
try {
 $buffer=New-Object byte[] 1048576
 while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
  $bytes=New-Object byte[] $count
  [Array]::Copy($buffer,$bytes,$count)
  $sha=[Security.Cryptography.SHA256]::Create()
  $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
  $name="chunk-$hash.bin"
  [IO.File]::WriteAllBytes((Join-Path $out $name),$bytes)
  $chunks+=@{sha256=$hash;size=$count;url="https://github.com/Azugawa/Personality_DeskPet/releases/download/v$Version/$name"}
 }
} finally {$stream.Dispose()}
$manifest=Get-Content (Join-Path $out 'update.json') -Raw | ConvertFrom-Json
$manifest | Add-Member -NotePropertyName resource_update -NotePropertyValue @{
 format=1;engine='4.7.2';chunk_size=1048576;chunks=$chunks
 sha256=(Get-FileHash (Join-Path $repo 'build/windows/DeskPet.pck')).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $out 'update.json')
