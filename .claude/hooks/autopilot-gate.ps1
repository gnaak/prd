# Stop hook — autopilot 모드(.claude/_autopilot 존재)에서 파이프라인이 미완료면 턴 종료를 막고 다음 단계를 지시
# 단일 프로젝트(flat) 구조: repo 루트의 contract/ 01_FEAT.md 02_PAGE.md pages/ docs/ 를 판정한다
# 핵심: 완료 판정은 파일 개수가 아니라 "내용"으로 한다 — 02_PAGE.md '파일' 컬럼의 모든 페이지가
#       비어있지 않고 common.css를 import해야 3단계를 넘어간다 (빈 <html></html> 스텁 통과 금지).
# 안전장치: 같은 단계에서 진전 없이 막힌 연속 횟수가 상한(단계별 차등)에 도달하면 마커를 거두고
#           무조건 종료 허용 (무한 루프 방지). 단계가 바뀌면(=진전) 카운터는 0으로 리셋된다.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$null = [Console]::In.ReadToEnd()

if (-not (Test-Path '.claude/_autopilot')) { exit 0 }

$cf = '.claude/_autopilot_count'   # 연속 스톨 횟수
$sf = '.claude/_autopilot_stage'   # 마지막으로 지시한 단계 태그(ascii)

# ---- 페이지 완성도 검사 ----
# 빈 <html></html> 스텁(15B)이나 common.css를 import하지 않은 페이지는 "미완성"으로 본다.
# 이 검사가 없으면 빈 파일도 개수에 잡혀 완료 게이트를 그대로 통과한다(과거 실패 원인).
function Test-PageComplete([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    if ((Get-Item $path).Length -lt 400) { return $false }
    return ((Get-Content $path -Raw) -match 'assets/css/common\.css')
}

# ---- 파이프라인 상태 판정 (앞 단계부터) ----
# $next   = main에게 줄 한국어 지시
# $stage  = 진전 감지용 ascii 태그 (단계가 바뀌면 카운터 리셋)
$next = ''
$stage = ''

$pdfs = @(Get-ChildItem -Path 'contract' -Filter '*.pdf' -ErrorAction SilentlyContinue)

if ($pdfs.Count -eq 0) {
    # 계약서가 없으면 진행 불가 — autopilot 해제 후 사용자 안내
    Remove-Item '.claude/_autopilot', $cf, $sf -Force -ErrorAction SilentlyContinue
    $msg = '[autopilot 중단] contract/에 기획서(계약서) PDF가 없다. 사용자에게 contract/ 폴더에 PDF를 넣어달라고 안내하고 종료하라.'
    $out = @{ decision = 'block'; reason = $msg } | ConvertTo-Json -Depth 3 -Compress
    Write-Output $out
    exit 0
}
elseif (-not (Test-Path '01_FEAT.md')) {
    $stage = 'feat'
    $next = '1단계 시작: Task(subagent_type="feat-writer")로 contract/의 PDF에서 01_FEAT.md를 생성하라.'
}
elseif (-not (Test-Path '.claude/_reviewed_stage1')) {
    $stage = 'review1'
    $next = '1단계 검토: Task(subagent_type="reviewer")로 01_FEAT.md를 검토받고, 블로커 해소 + 권고 반영 후 New-Item -Path ".claude/_reviewed_stage1" -ItemType File -Force 로 마커를 생성하라. (대규모 재작성이 필요하면 feat-writer에 punch list를 넘겨 재작성)'
}
elseif (-not (Test-Path '02_PAGE.md')) {
    $stage = 'page'
    $next = '2단계 시작: Task(subagent_type="page-mapper")로 01_FEAT.md 기반 02_PAGE.md를 생성하라 (페이지 목록 표에 파일 컬럼 필수).'
}
elseif (-not (Test-Path '.claude/_reviewed_stage2')) {
    $stage = 'review2'
    $next = '2단계 검토: reviewer로 02_PAGE.md를 검토받고, 반영 완료 후 ".claude/_reviewed_stage2" 마커를 생성하라.'
}
else {
    # ----- 3단계: 02_PAGE.md의 '파일' 컬럼을 기준으로 P#↔파일 1:1 + 각 파일의 완성도를 검증 -----
    # 기대 파일 집합 = 표에 적힌 user/xxx.html · admin/xxx.html 토큰 (URL엔 .html이 없어 오검출 없음)
    $expectedFiles = @()
    if (Test-Path '02_PAGE.md') {
        $content = Get-Content '02_PAGE.md' -Raw
        $expectedFiles = @([regex]::Matches($content, '(user|admin)/[A-Za-z0-9_\-]+\.html') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    }
    $expected = $expectedFiles.Count

    # 미완성 = 기대 파일 중 없거나 / 빈 스텁이거나 / common.css 미import (개수가 아니라 내용으로 판정)
    $incomplete = @($expectedFiles | Where-Object { -not (Test-PageComplete "pages/$_") })
    $done = $expected - $incomplete.Count

    # 고아 = 디스크에 있으나 표에 없는 user/admin 페이지 (드리프트 감지)
    $actualRel = @()
    foreach ($d in 'user', 'admin') {
        if (Test-Path "pages/$d") {
            Get-ChildItem "pages/$d" -Filter '*.html' -ErrorAction SilentlyContinue | ForEach-Object { $actualRel += "$d/$($_.Name)" }
        }
    }
    $orphans = @($actualRel | Where-Object { $expectedFiles -notcontains $_ })

    # foundation = css + 허브 + 사용자 exemplar 1장 + 관리자 exemplar 1장이 모두 존재 (재빌드 시 exemplar 누락 방지)
    $hasFoundation = (Test-Path 'pages/assets/css/common.css') -and (Test-Path 'pages/index.html') -and `
    (@(Get-ChildItem 'pages/user' -Filter '*.html' -ErrorAction SilentlyContinue).Count -gt 0) -and `
    (@(Get-ChildItem 'pages/admin' -Filter '*.html' -ErrorAction SilentlyContinue).Count -gt 0)

    if ($expected -eq 0) {
        $stage = 'page-files'
        $next = "02_PAGE.md 페이지 목록 표에 '파일' 컬럼(user/xxx.html · admin/xxx.html)이 없다. Task(subagent_type=`"page-mapper`")로 표를 갱신해 모든 P#에 파일 칸을 채워라 — 완료 게이트가 이 컬럼으로 페이지 완성도를 검증한다."
    }
    elseif (-not $hasFoundation) {
        $stage = 'foundation'
        $next = "3단계 기반: Task(subagent_type=`"ui-foundation`")로 pages/assets/css/common.css + pages/index.html 허브 + 사용자/관리자 exemplar 페이지를 생성하라. exemplar(홈/대시보드)가 빈 <html></html> 스텁이면 안 된다 — 반환 전 각 파일을 Read로 확인하라."
    }
    elseif ($incomplete.Count -gt 0) {
        # 한 장이라도 완성되면 $done 이 바뀌어 $stage 가 바뀌므로 양산 중엔 스톨로 안 친다
        $stage = "build-$done-of-$expected"
        $miss = (($incomplete | Select-Object -First 6) -join ', ')
        $next = "3단계 페이지 제작: $done/$expected 완료. 미완성(없음/빈 스텁/common.css 미import): $miss. 남은 페이지를 Task(subagent_type=`"html-builder`")로 페이지당 1호출씩 병렬 생성하라 (출력 경로 = 02_PAGE.md '파일' 칸, exemplar 경로를 프롬프트에 명시). 빈 <html></html> 스텁은 미완성으로 친다 — 실제 내용을 채워라."
    }
    elseif ($orphans.Count -gt 0) {
        $stage = 'orphans'
        $orph = (($orphans | Select-Object -First 6) -join ', ')
        $next = "정리: 02_PAGE.md 표에 없는 고아 페이지가 있다 ($orph). 표에 추가(필요한 페이지면)하거나 삭제(불필요하면)해 P#↔파일을 1:1로 맞춰라."
    }
    elseif (-not (Test-Path '.claude/_reviewed_stage3')) {
        $stage = 'review3'
        $next = "3단계 검토: (1) Task(subagent_type=`"linter`")로 pages/ 기계적 검사 → 위반(빈 파일/깨진 링크 포함) 수정, (2) reviewer로 전체 검토 → 반영, (3) `".claude/_reviewed_stage3`" 마커 생성. (전 페이지가 비어있지 않고 common.css를 import함은 게이트가 이미 보장한다.)"
    }
    elseif (-not (Test-Path '.claude/_docs_done')) {
        $stage = 'docs'
        $next = "마무리: Task(subagent_type=`"docs-builder`")로 docs/index.html을 생성/갱신하고, 확인 후 `".claude/_docs_done`" 마커를 생성하고 사용자에게 최종 완료 보고를 하라."
    }
    else {
        # 전부 완료 — autopilot 해제하고 종료 허용
        Remove-Item '.claude/_autopilot', $cf, $sf -Force -ErrorAction SilentlyContinue
        exit 0
    }
}

# ---- 진행도 기반 스톨 카운터 ----
# 단계별 차등 상한: 양산/검토(build-*, review3)는 정상적으로 여러 턴 걸리므로 넉넉히(20),
# 단발 생성(생성 1회면 끝나는) 단계는 타이트하게(8) 둬서 막힘을 빨리 감지한다.
$cap = 8
if ($stage -like 'build-*' -or $stage -eq 'review3') { $cap = 20 }

$prevStage = ''
if (Test-Path $sf) { $prevStage = (Get-Content $sf -Raw).Trim() }
$n = 0
if (Test-Path $cf) { try { $n = [int]((Get-Content $cf -Raw).Trim()) } catch { $n = 0 } }

if ($stage -eq $prevStage) { $n = $n + 1 } else { $n = 1 }  # 단계가 그대로면 스톨++ / 바뀌면 리셋

if ($n -ge $cap) {
    # 같은 단계에서 cap 턴 연속 진전 없음 → 안전 해제
    Remove-Item '.claude/_autopilot', $cf, $sf -Force -ErrorAction SilentlyContinue
    $msg = "[autopilot 중단] '$stage' 단계에서 $cap턴 연속 진전이 없어 autopilot을 자동 해제했다. 현재까지 상태를 사용자에게 보고하고, 무엇이 막혔는지(reviewer 블로커/스코프 문제 등) 설명하라. 이어서 진행하려면 사용자가 다시 진행 신호를 주면 된다."
    $out = @{ decision = 'block'; reason = $msg } | ConvertTo-Json -Depth 3 -Compress
    Write-Output $out
    exit 0
}

$n    | Set-Content $cf -Encoding ascii
$stage | Set-Content $sf -Encoding ascii

$reason = "[autopilot $stage $n/$cap] 파이프라인이 아직 끝나지 않았다. 다음 단계를 지금 실행하라 → $next 단, reviewer가 같은 단계에서 블로커를 2회 연속 보고했거나 사용자에게 물어야만 하는 상황이면: 상황을 보고하고 Remove-Item `".claude/_autopilot`" 실행 후 종료하라."

$out = @{
    decision = 'block'
    reason   = $reason
} | ConvertTo-Json -Depth 3 -Compress
Write-Output $out
