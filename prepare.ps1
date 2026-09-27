# 청년 정책 대시보드용 데이터 가공
# 입력: serviceList.json, supportConditions.json, fetch-meta.json (fetch.ps1이 받은 원본)
# 출력: youth.json (나이 조건이 15~39세 안에 들어가는 '청년 중심' 정책만), meta.json (받은 날짜와 건수)
# 데이터 폴더: 환경변수 DATA_DIR, 없으면 상위 폴더의 data
$ErrorActionPreference = "Stop"
$dataDir = if ($env:DATA_DIR) { $env:DATA_DIR } else { Join-Path $PSScriptRoot "..\data" }
$today = (Get-Date).Date
$utf8 = New-Object Text.UTF8Encoding $false

$list = [IO.File]::ReadAllText((Join-Path $dataDir "serviceList.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
$cond = [IO.File]::ReadAllText((Join-Path $dataDir "supportConditions.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
$condById = @{}; foreach ($c in $cond) { $condById[$c.'서비스ID'] = $c }

# --- 지역: 기관명 앞부분에서 시·도, 시·군·구를 뽑고, 이름에 지역이 없는 기관은 기관코드로 찾는다
$sidoPattern = '^(\S+?(특별시|광역시|특별자치시|특별자치도|통합특별시|도))(교육청)?$'
function Split-Region([string]$name) {
  $parts = $name -split '\s+'
  if ($parts.Count -ge 1 -and $parts[0] -match $sidoPattern) {
    $sigungu = if ($parts.Count -ge 2) { $parts[1] } else { "" }
    return @($Matches[1], $sigungu)
  }
  return $null
}
$regionByCode = @{}
foreach ($s in $list) {
  if ($s.'소관기관유형' -in @('시군구', '광역시도')) {
    $r = Split-Region $s.'소관기관명'
    if ($r -and -not $regionByCode.ContainsKey($s.'소관기관코드')) { $regionByCode[$s.'소관기관코드'] = $r }
  }
}
function Get-Region($s) {
  if ($s.'소관기관유형' -in @('중앙행정기관', '공공기관')) { return @('전국', '') }
  $r = Split-Region $s.'소관기관명'
  if ($r) { return $r }
  if ($regionByCode.ContainsKey($s.'소관기관코드')) { return $regionByCode[$s.'소관기관코드'] }
  return @('확인 필요', '')
}

# --- 신청기한: 날짜를 읽을 수 있으면 시작일·마감일을, 아니면 유형만 남긴다
function Read-Dates([string]$t) {
  $dates = New-Object System.Collections.ArrayList
  $year = $null
  $ms = [regex]::Matches($t, '(?:(20\d{2})\s*[.\-년]\s*)?(\d{1,2})\s*[.\-월]\s*(\d{1,2})(?!\d)')
  foreach ($m in $ms) {
    if ($m.Groups[1].Success) { $year = [int]$m.Groups[1].Value }
    if ($null -eq $year) { continue }
    $mo = [int]$m.Groups[2].Value; $d = [int]$m.Groups[3].Value
    if ($mo -lt 1 -or $mo -gt 12 -or $d -lt 1 -or $d -gt 31) { continue }
    try { [void]$dates.Add((Get-Date -Year $year -Month $mo -Day $d).Date) } catch { }
  }
  return $dates
}
function Get-Deadline([string]$t) {
  if ([string]::IsNullOrWhiteSpace($t)) { return @{ kind = 'check' } }
  if ($t -match '불필요') { return @{ kind = 'none' } }
  if ($t -match '20\d{2}\s*[.\-년]\s*\d{1,2}\s*[.\-월]\s*\d{1,2}') {
    $ds = Read-Dates $t
    if ($ds.Count -gt 0) {
      $start = ($ds | Measure-Object -Minimum).Minimum
      $end = ($ds | Measure-Object -Maximum).Maximum
      $kind = if ($end -lt $today) { 'closed' } elseif ($start -gt $today) { 'upcoming' } else { 'open' }
      return @{ kind = $kind; start = $start.ToString('yyyy-MM-dd'); end = $end.ToString('yyyy-MM-dd') }
    }
  }
  if ($t -match '상시') { return @{ kind = 'always' } }
  return @{ kind = 'check' }
}

function Cut([string]$s, [int]$n) {
  if (-not $s) { return "" }
  $s = ($s -replace '\r', '').Trim()
  if ($s.Length -gt $n) { return $s.Substring(0, $n).TrimEnd() + "…" }
  return $s
}

$out = foreach ($s in $list) {
  $c = $condById[$s.'서비스ID']
  if (-not $c -or $null -eq $c.JA0110 -or $null -eq $c.JA0111) { continue }
  $mn = [int]$c.JA0110; $mx = [int]$c.JA0111
  if (-not ($mn -ge 15 -and $mx -le 39 -and $mn -le 34 -and $mx -ge 19)) { continue }
  $reg = Get-Region $s
  $dl = Get-Deadline $s.'신청기한'
  [ordered]@{
    id = $s.'서비스ID'
    name = $s.'서비스명'
    summary = $s.'서비스목적요약'
    support = Cut $s.'지원내용' 400
    target = Cut $s.'지원대상' 1200
    criteria = Cut $s.'선정기준' 800
    field = $s.'서비스분야'
    type = $s.'지원유형'
    org = $s.'소관기관명'
    sido = $reg[0]
    sigungu = $reg[1]
    ageMin = $mn
    ageMax = $mx
    deadline = ($s.'신청기한' -replace '\r', '').Trim()
    kind = $dl.kind
    start = $dl.start
    end = $dl.end
    how = ($s.'신청방법' -replace '\|\|', ', ')
    url = $s.'상세조회URL'
    updated = $s.'수정일시'
  }
}

$json = $out | ConvertTo-Json -Depth 4 -Compress
[IO.File]::WriteAllText((Join-Path $dataDir "youth.json"), $json, $utf8)

$fetchMetaFile = Join-Path $dataDir "fetch-meta.json"
$fetchedAt = if (Test-Path $fetchMetaFile) { ([IO.File]::ReadAllText($fetchMetaFile, [Text.Encoding]::UTF8) | ConvertFrom-Json).fetchedAt } else { (Get-Item (Join-Path $dataDir "serviceList.json")).LastWriteTime.ToString("yyyy-MM-dd") }
$meta = @{ fetchedAt = $fetchedAt; total = $list.Count; youth = @($out).Count } | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $dataDir "meta.json"), $meta, $utf8)

"청년 중심 정책: $($out.Count)건"
$out | Group-Object { $_.kind } | Sort-Object Count -Descending | ForEach-Object { "  {0,-9} {1,4}" -f $_.Name, $_.Count }
"지역 확인 필요: $(($out | Where-Object { $_.sido -eq '확인 필요' }).Count)건"
$out | Where-Object { $_.sido -eq '확인 필요' } | Select-Object -First 5 | ForEach-Object { "  - $($_.org)" }
"시·도 목록:"; ($out | Group-Object { $_.sido } | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
