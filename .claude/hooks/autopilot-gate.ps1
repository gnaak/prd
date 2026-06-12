# Stop hook — autopilot 모드(.claude/_autopilot 존재)에서 파이프라인이 미완료면 턴 종료를 막고 다음 단계를 지시
# 안전장치: 카운터(.claude/_autopilot_count)가 상한에 도달하면 마커를 거두고 무조건 종료 허용 (무한 루프 방지)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$null = [Console]::In.ReadToEnd()

if (-not (Test-Path '.claude/_autopilot')) { exit 0 }

# ---- 무한 루프 가드 ----
$cf = '.claude/_autopilot_count'
$n = 0
if (Test-Path $cf) {
    try { $n = [int]((Get-Content $cf -Raw).Trim()) } catch { $n = 0 }
}
if ($n -ge 20) {
    Remove-Item '.claude/_autopilot' -Force -ErrorAction SilentlyContinue
    Remove-Item $cf -Force -ErrorAction SilentlyContinue
    exit 0
}

# ---- 파이프라인 상태 판정 (앞 단계부터) ----
$next = ''

if (-not (Test-Path '01_FEAT.md')) {
    $next = '1단계 시작: Task(subagent_type="feat-writer")로 contract/의 PDF에서 01_FEAT.md를 생성하라.'
}
elseif (-not (Test-Path '.claude/_reviewed_stage1')) {
    $next = '1단계 검토: Task(subagent_type="reviewer")로 01_FEAT.md를 검토받고, 블로커 해소 + 권고 반영 후 New-Item -Path ".claude/_reviewed_stage1" -ItemType File -Force 로 마커를 생성하라. (대규모 재작성이 필요하면 feat-writer에 punch list를 넘겨 재작성)'
}
elseif (-not (Test-Path '02_PAGE.md')) {
    $next = '2단계 시작: Task(subagent_type="page-mapper")로 02_PAGE.md를 생성하라.'
}
elseif (-not (Test-Path '.claude/_reviewed_stage2')) {
    $next = '2단계 검토: reviewer로 02_PAGE.md를 검토받고, 반영 완료 후 ".claude/_reviewed_stage2" 마커를 생성하라.'
}
else {
    # 3단계 산출물 카운트
    $expected = 0
    if (Test-Path '02_PAGE.md') {
        $content = Get-Content '02_PAGE.md' -Raw
        $expected = @([regex]::Matches($content, '\bP\d+\b') | ForEach-Object { $_.Value } | Sort-Object -Unique).Count
    }
    $count = 0
    if (Test-Path 'pages\user') { $count += (Get-ChildItem -Path 'pages\user' -Filter '*.html' -ErrorAction SilentlyContinue).Count }
    if (Test-Path 'pages\admin') { $count += (Get-ChildItem -Path 'pages\admin' -Filter '*.html' -ErrorAction SilentlyContinue).Count }
    $hasFoundation = (Test-Path 'pages\assets\css\common.css') -and (Test-Path 'pages\index.html')

    if (-not $hasFoundation) {
        $next = '3단계 기반: Task(subagent_type="ui-foundation")로 common.css + pages/index.html 허브 + 사용자/관리자 exemplar 페이지를 생성하라.'
    }
    elseif ($expected -gt 0 -and $count -lt $expected) {
        $next = "3단계 페이지 제작: 현재 ${count}/${expected}개. 남은 페이지를 Task(subagent_type=`"html-builder`")로 페이지당 1호출씩 병렬 생성하라 (exemplar 경로를 프롬프트에 명시)."
    }
    elseif (-not (Test-Path '.claude/_reviewed_stage3')) {
        $next = '3단계 검토: (1) Task(subagent_type="linter")로 기계적 검사 → 위반 수정, (2) reviewer로 전체 검토 → 반영, (3) ".claude/_reviewed_stage3" 마커 생성.'
    }
    elseif (-not (Test-Path '.claude/_docs_done')) {
        $next = '마무리: Task(subagent_type="docs-builder")로 docs/index.html을 생성/갱신하고, 확인 후 ".claude/_docs_done" 마커를 생성한 뒤 사용자에게 최종 완료 보고를 하라.'
    }
    else {
        # 전부 완료 — autopilot 해제하고 종료 허용
        Remove-Item '.claude/_autopilot' -Force -ErrorAction SilentlyContinue
        Remove-Item $cf -Force -ErrorAction SilentlyContinue
        exit 0
    }
}

# 카운터 증가 + 종료 차단
($n + 1) | Set-Content $cf -Encoding ascii
$reason = "[autopilot $($n + 1)/20] 파이프라인이 아직 끝나지 않았다. 다음 단계를 지금 실행하라 → $next 단, reviewer가 같은 단계에서 블로커를 2회 연속 보고했거나 사용자에게 물어야만 하는 상황이면: 상황을 보고하고 Remove-Item `".claude/_autopilot`" 실행 후 종료하라."

$out = @{
    decision = 'block'
    reason   = $reason
} | ConvertTo-Json -Depth 3 -Compress
Write-Output $out
