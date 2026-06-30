# Stop hook — autopilot 모드(.claude/_autopilot 존재)에서 파이프라인이 미완료면 턴 종료를 막고 다음 단계를 지시
# 고객사별 구조: .claude/_current_client 의 slug로 html/clients/{slug}/ 를 대상으로 판정한다
# 안전장치: "같은 단계에서 진전 없이 막힌 연속 횟수"가 상한(STALL_CAP)에 도달하면 마커를 거두고
#           무조건 종료 허용 (무한 루프 방지). 단계가 바뀌면(=진전) 카운터는 0으로 리셋되므로
#           페이지가 많거나 reviewer 재검토가 길어도 정상 진행이면 카운터가 누적되지 않는다.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$null = [Console]::In.ReadToEnd()

if (-not (Test-Path '.claude/_autopilot')) { exit 0 }

$STALL_CAP = 12
$cf = '.claude/_autopilot_count'   # 연속 스톨 횟수
$sf = '.claude/_autopilot_stage'   # 마지막으로 지시한 단계 태그(ascii)

# ---- 현재 고객사 base 경로 ----
$slug = ''
if (Test-Path '.claude/_current_client') { $slug = (Get-Content '.claude/_current_client' -Raw).Trim() }
$base = ''
if ($slug) { $base = "html/clients/$slug" }

# ---- 파이프라인 상태 판정 (앞 단계부터) ----
# $next   = main에게 줄 한국어 지시
# $stage  = 진전 감지용 ascii 태그 (단계가 바뀌면 카운터 리셋)
$next = ''
$stage = ''

if (-not $slug -or -not (Test-Path $base)) {
    $stage = 'stage0'
    $next = '0단계 클라이언트 셋업: Task(subagent_type="client-init")로 html/_inbox/의 새 계약서에서 slug/메타(client.json)를 만든 뒤, PDF를 html/clients/{slug}/contract/로 옮기고(Move-Item — git mv 아님) ".claude/_current_client"에 그 slug를 기록하라.'
}
elseif (-not (Test-Path "$base/01_FEAT.md")) {
    $stage = 'feat'
    $next = "1단계 시작: Task(subagent_type=`"feat-writer`")로 $base/contract/의 PDF에서 $base/01_FEAT.md를 생성하라."
}
elseif (-not (Test-Path '.claude/_reviewed_stage1')) {
    $stage = 'review1'
    $next = "1단계 검토: Task(subagent_type=`"reviewer`")로 $base/01_FEAT.md를 검토받고, 블로커 해소 + 권고 반영 후 New-Item -Path `".claude/_reviewed_stage1`" -ItemType File -Force 로 마커를 생성하라. (대규모 재작성이 필요하면 feat-writer에 punch list를 넘겨 재작성)"
}
elseif (-not (Test-Path "$base/02_PAGE.md")) {
    $stage = 'page'
    $next = "2단계 시작: Task(subagent_type=`"page-mapper`")로 $base/01_FEAT.md 기반 $base/02_PAGE.md를 생성하라."
}
elseif (-not (Test-Path '.claude/_reviewed_stage2')) {
    $stage = 'review2'
    $next = "2단계 검토: reviewer로 $base/02_PAGE.md를 검토받고, 반영 완료 후 `".claude/_reviewed_stage2`" 마커를 생성하라."
}
else {
    # 3단계 산출물 카운트 (해당 고객사 폴더 기준)
    # expected = 02_PAGE.md "페이지 목록" 표의 행 수 = 표 셀 첫 칸이 P#인 줄만 카운트
    #            (트리/본문에 흩어진 P# 언급이나 오타 P# 가 expected를 부풀리지 않도록 표 행에 고정)
    $expected = 0
    if (Test-Path "$base/02_PAGE.md") {
        $content = Get-Content "$base/02_PAGE.md" -Raw
        $expected = @([regex]::Matches($content, '(?m)^\s*\|\s*(P\d+)\b') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique).Count
    }
    $count = 0
    if (Test-Path "$base/pages/user") { $count += (Get-ChildItem -Path "$base/pages/user" -Filter '*.html' -ErrorAction SilentlyContinue).Count }
    if (Test-Path "$base/pages/admin") { $count += (Get-ChildItem -Path "$base/pages/admin" -Filter '*.html' -ErrorAction SilentlyContinue).Count }
    $hasFoundation = (Test-Path "$base/pages/assets/css/common.css") -and (Test-Path "$base/pages/index.html")

    if (-not $hasFoundation) {
        $stage = 'foundation'
        $next = "3단계 기반: Task(subagent_type=`"ui-foundation`")로 $base/pages/assets/css/common.css + $base/pages/index.html 허브 + 사용자/관리자 exemplar 페이지를 생성하라."
    }
    elseif ($expected -gt 0 -and $count -lt $expected) {
        # 페이지가 한 장이라도 늘면 $stage 가 바뀌어 카운터가 리셋된다 → 양산 중엔 스톨로 안 친다
        $stage = "build-$count-of-$expected"
        $next = "3단계 페이지 제작: 현재 ${count}/${expected}개. 남은 페이지를 Task(subagent_type=`"html-builder`")로 페이지당 1호출씩 병렬 생성하라 ($base/pages/ 밑에 생성, exemplar 경로를 프롬프트에 명시). 02_PAGE.md의 페이지 표(P#)와 실제 파일이 1:1이 되도록 하라 — 두 페이지를 한 파일로 합치면 카운트가 영영 안 맞는다."
    }
    elseif (-not (Test-Path '.claude/_reviewed_stage3')) {
        $stage = 'review3'
        $next = "3단계 검토: (1) Task(subagent_type=`"linter`")로 $base/pages/ 기계적 검사 → 위반 수정, (2) reviewer로 전체 검토 → 반영, (3) `".claude/_reviewed_stage3`" 마커 생성."
    }
    elseif (-not (Test-Path '.claude/_docs_done')) {
        $stage = 'docs'
        $next = "마무리: Task(subagent_type=`"docs-builder`")로 $base/docs/index.html을 생성/갱신하고, 확인 후 $base/client.json의 status를 `"delivered`"로 바꾼 뒤 `".claude/_docs_done`" 마커를 생성하고 사용자에게 최종 완료 보고를 하라."
    }
    else {
        # 전부 완료 — autopilot 해제하고 종료 허용
        Remove-Item '.claude/_autopilot', $cf, $sf -Force -ErrorAction SilentlyContinue
        exit 0
    }
}

# ---- 진행도 기반 스톨 카운터 ----
$prevStage = ''
if (Test-Path $sf) { $prevStage = (Get-Content $sf -Raw).Trim() }
$n = 0
if (Test-Path $cf) { try { $n = [int]((Get-Content $cf -Raw).Trim()) } catch { $n = 0 } }

if ($stage -eq $prevStage) { $n = $n + 1 } else { $n = 1 }  # 단계가 그대로면 스톨++ / 바뀌면 리셋

if ($n -ge $STALL_CAP) {
    # 같은 단계에서 STALL_CAP 턴 연속 진전 없음 → 안전 해제
    Remove-Item '.claude/_autopilot', $cf, $sf -Force -ErrorAction SilentlyContinue
    $msg = "[autopilot 중단] '$stage' 단계에서 $STALL_CAP턴 연속 진전이 없어 autopilot을 자동 해제했다. 현재까지 상태를 사용자에게 보고하고, 무엇이 막혔는지(reviewer 블로커/스코프 문제 등) 설명하라. 이어서 진행하려면 사용자가 다시 진행 신호를 주면 된다."
    $out = @{ decision = 'block'; reason = $msg } | ConvertTo-Json -Depth 3 -Compress
    Write-Output $out
    exit 0
}

$n    | Set-Content $cf -Encoding ascii
$stage | Set-Content $sf -Encoding ascii

$reason = "[autopilot $stage $n/$STALL_CAP] 파이프라인이 아직 끝나지 않았다 (고객사: $slug). 다음 단계를 지금 실행하라 → $next 단, reviewer가 같은 단계에서 블로커를 2회 연속 보고했거나 사용자에게 물어야만 하는 상황이면: 상황을 보고하고 Remove-Item `".claude/_autopilot`" 실행 후 종료하라."

$out = @{
    decision = 'block'
    reason   = $reason
} | ConvertTo-Json -Depth 3 -Compress
Write-Output $out
