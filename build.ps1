# dashboard.src.html에 youth.json과 meta.json을 넣어 index.html(배포용)을 만든다
# PC에서 실행하면 상위 폴더에 dashboard.html(Claude 아티팩트 게시용)도 만든다
$ErrorActionPreference = "Stop"
$utf8 = New-Object Text.UTF8Encoding $false
$dataDir = if ($env:DATA_DIR) { $env:DATA_DIR } else { Join-Path $PSScriptRoot "..\data" }

$src = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "dashboard.src.html"), [Text.Encoding]::UTF8)
$data = [IO.File]::ReadAllText((Join-Path $dataDir "youth.json"), [Text.Encoding]::UTF8).Trim().Replace("</", "<\/")
$meta = [IO.File]::ReadAllText((Join-Path $dataDir "meta.json"), [Text.Encoding]::UTF8).Trim()
$body = $src.Replace("/*__DATA__*/[]", $data).Replace("/*__META__*/{}", $meta)

$page = "<!doctype html>`n<html lang=`"ko`">`n<head>`n<meta charset=`"utf-8`">`n<meta name=`"viewport`" content=`"width=device-width, initial-scale=1, viewport-fit=cover`">`n</head>`n<body>`n" + $body + "`n</body>`n</html>`n"
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "index.html"), $page, $utf8)
"index.html: $([int]((Get-Item (Join-Path $PSScriptRoot 'index.html')).Length / 1KB)) KB"

if (-not $env:GITHUB_ACTIONS) {
  $artifact = Join-Path $PSScriptRoot "..\dashboard.html"
  [IO.File]::WriteAllText($artifact, $body, $utf8)
  "dashboard.html: $([int]((Get-Item $artifact).Length / 1KB)) KB"
}
