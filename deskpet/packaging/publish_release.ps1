param([string]$Version = "0.2.9")
$ErrorActionPreference = 'Stop'
$env:GCM_INTERACTIVE = 'never'
$credentialResult = "protocol=https`nhost=github.com`n`n" | git credential fill
$secretLine = $credentialResult | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
if (-not $secretLine) { throw 'GitHub credential unavailable' }
$token = $secretLine.Substring(9)
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'DeskPet-Release' }
$api = 'https://api.github.com/repos/Azugawa/Personality_DeskPet/releases'
$all = Invoke-RestMethod -Uri "$api`?per_page=100" -Headers $headers
$existing = $all | Where-Object tag_name -eq "v$Version" | Select-Object -First 1
if ($existing -and -not $existing.draft) { throw 'Release already published; refusing to replace assets' }
$body = @{
 tag_name = "v$Version"
 target_commitish = (git rev-parse HEAD)
 name = "何爪爪 v$Version"
 draft = $true
 body = "优化启动速度：动画切帧与去背景改为构建时处理。整理动画与 UI 素材目录。新增提起、抛掷反弹、摔倒和起身，普通松手可自由放置。缩小透明窗口，校准动画角色尺寸。支持兼容版本分块增量更新，无需反复运行安装向导。旧版本首次升级仍需安装新版更新器。"
} | ConvertTo-Json
if ($existing) { $release = $existing } else { $release = Invoke-RestMethod -Method Post -Uri $api -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) }
$manifest = Get-Content 'E:/DeskPet/build/installer/update.json' -Raw | ConvertFrom-Json
$filenames = @("DeskPet-Setup-$Version.exe","update.json") + @($manifest.resource_update.chunks | ForEach-Object { ([Uri]$_.url).Segments[-1] } | Select-Object -Unique)
foreach ($filename in $filenames) {
 $asset = @($release.assets) | Where-Object name -eq $filename
 if ($asset) { if ($asset.size -ne (Get-Item (Join-Path "E:/DeskPet/build/installer" $filename)).Length) { throw "Existing size mismatch" }; Write-Output "Verified existing $filename"; continue }
 $path = Join-Path 'E:/DeskPet/build/installer' $filename
 $url = "https://uploads.github.com/repos/Azugawa/Personality_DeskPet/releases/$($release.id)/assets?name=$filename"
 $config = "header = `"Authorization: Bearer $token`"`nheader = `"Content-Type: application/octet-stream`""
 $response = $config | curl.exe -4 --config - --http1.1 --silent --show-error --fail --connect-timeout 15 --max-time 240 --retry 3 --retry-all-errors --request POST --data-binary "@$path" $url
 if ($LASTEXITCODE -ne 0) { throw "Upload failed: $filename" }
 $uploaded = $response | ConvertFrom-Json
 if ($uploaded.size -ne (Get-Item $path).Length) { throw 'Uploaded size mismatch' }
 Write-Output "Uploaded $filename ($($uploaded.size) bytes)"
}
$published = Invoke-RestMethod -Method Patch -Uri "$api/$($release.id)" -Headers $headers -ContentType 'application/json' -Body '{"draft":false,"make_latest":"true"}'
Write-Output $published.html_url
$latest = Invoke-RestMethod -Uri "$api/latest" -Headers $headers
Write-Output "Latest=$($latest.tag_name); Draft=$($latest.draft); Assets=$($latest.assets.name -join ', ')"

