param([string]$Version = "0.3.0")
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
 body = @"
何爪爪 v$Version

- 新增定时提醒：指定日期时间或倒计时，支持启动补提醒、稍后提醒。
- 新增和风天气：1km 格点、系统/手动定位、今天与明天对比建议，并按和风要求署名。
- 新增工作模式：Word/WPS/PPT/Excel/PDF 白名单自动开关，40 分钟工作 / 5 分钟休息，全屏课堂延后提醒。
- 新增系统状态哨兵：CPU 占用、前台程序、空闲时间、C 盘空间和 Top 进程。
- 新增 C 盘非必要文件分析：Windows 搜索索引优先，索引不可用时定向扫描；只读，不自动删除或移动。
- 新增本地设置存储与开机自启。
- 0.2.9 及更早版本首次升级建议使用完整安装包；安装器默认勾选开机自启，也可在设置里修改。
"@
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

