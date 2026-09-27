# 행정안전부 「대한민국 공공서비스(혜택) 정보」 API에서 전체 목록과 지원조건을 받는다
# 키: GitHub Actions에서는 환경변수 DATA_GO_KR_KEY(Secrets), PC에서는 상위 폴더의 api.txt
# 저장 위치: 환경변수 DATA_DIR, 없으면 상위 폴더의 data (저장소 밖)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$utf8 = New-Object Text.UTF8Encoding $false

$key = $env:DATA_GO_KR_KEY
if (-not $key) {
  $keyFile = Join-Path $PSScriptRoot "..\api.txt"
  if (-not (Test-Path $keyFile)) { throw "API 키가 없습니다. DATA_GO_KR_KEY 환경변수나 api.txt를 준비하세요." }
  $key = [IO.File]::ReadAllText($keyFile, [Text.Encoding]::UTF8)
}
$enc = [uri]::EscapeDataString($key.Trim())

$dataDir = if ($env:DATA_DIR) { $env:DATA_DIR } else { Join-Path $PSScriptRoot "..\data" }
New-Item -ItemType Directory -Force $dataDir | Out-Null

$total = 0
foreach ($op in @("serviceList", "supportConditions")) {
  $all = New-Object System.Collections.ArrayList
  $page = 1
  do {
    $r = Invoke-RestMethod -Uri "https://api.odcloud.kr/api/gov24/v3/${op}?page=$page&perPage=1000&serviceKey=$enc" -TimeoutSec 120
    $all.AddRange(@($r.data))
    $page++
  } while ($all.Count -lt $r.totalCount -and $r.currentCount -gt 0)
  # 받다가 끊겨서 일부만 받았으면 멈춘다 (잘못된 데이터로 배포하지 않도록)
  if ($all.Count -lt $r.totalCount -or $all.Count -lt 1000) { throw "$op 을(를) $($all.Count)/$($r.totalCount)건만 받았습니다." }
  [IO.File]::WriteAllText((Join-Path $dataDir "$op.json"), ($all | ConvertTo-Json -Depth 5 -Compress), $utf8)
  "$op : $($all.Count)건"
  if ($op -eq "serviceList") { $total = $all.Count }
}

$kst = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, "Korea Standard Time")
$meta = @{ fetchedAt = $kst.ToString("yyyy-MM-dd"); total = $total } | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $dataDir "fetch-meta.json"), $meta, $utf8)
"받은 날짜(한국 시간): $($kst.ToString('yyyy-MM-dd HH:mm'))"
