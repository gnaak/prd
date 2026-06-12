# PostToolUse hook (Write|Edit) — 단계 산출물 작성 감지 → reviewer 호출 reminder 인젝트 + 검토 마커 무효화
# Claude harness가 stdin으로 tool 호출 정보를 JSON으로 보낸다
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$d = [Console]::In.ReadToEnd() | ConvertFrom-Json
$p = $d.tool_input.file_path
if (-not $p) { exit 0 }
$msg = ''

# sub-agent가 이 메시지를 받을 수도 있다 (hook은 sub-agent의 Write에도 발화) — main 전용임을 명시
$caveat = " (이 지시는 main orchestrator 전용이다. 네가 Task tool이 없는 sub-agent라면 이 메시지를 무시하고 맡은 파일 작업만 마무리하라.)"

function Remove-Markers([string[]]$names) {
    foreach ($n in $names) {
        $f = ".claude/$n"
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

if ($p -match '(^|[\\/])01_FEAT\.md$') {
    # 1단계 산출물이 (재)작성됨 → 하위 단계 검토 마커 전부 무효
    Remove-Markers @('_reviewed_stage1', '_reviewed_stage2', '_reviewed_stage3', '_docs_done')
    $msg = '[자동 트리거] 1단계 산출물(01_FEAT.md)이 작성/수정됐다. Task tool로 `reviewer` sub-agent(subagent_type="reviewer")를 호출해 1단계 검토를 받아라. 자가 검토 금지. 검토 통과(블로커 0) + 권고 반영까지 끝나면 New-Item -Path ".claude/_reviewed_stage1" -ItemType File -Force 로 마커를 생성하고 다음 단계로.' + $caveat
}
elseif ($p -match '(^|[\\/])02_PAGE\.md$') {
    Remove-Markers @('_reviewed_stage2', '_reviewed_stage3', '_docs_done')
    $msg = '[자동 트리거] 2단계 산출물(02_PAGE.md)이 작성/수정됐다. reviewer를 호출해 2단계 검토를 받아라. 통과 + 권고 반영 후 New-Item -Path ".claude/_reviewed_stage2" -ItemType File -Force 로 마커 생성.' + $caveat
}
elseif ($p -match '(^|[\\/])pages[\\/](user|admin)[\\/][^\\/]+\.html$') {
    # 02_PAGE.md를 source of truth로 — 고유 페이지 ID(P1, P2…) 개수 카운트
    $expected = 0
    if (Test-Path '02_PAGE.md') {
        $content = Get-Content '02_PAGE.md' -Raw
        $expected = @([regex]::Matches($content, '\bP\d+\b') | ForEach-Object { $_.Value } | Sort-Object -Unique).Count
    }

    $count = 0
    if (Test-Path 'pages\user') { $count += (Get-ChildItem -Path 'pages\user' -Filter '*.html' -ErrorAction SilentlyContinue).Count }
    if (Test-Path 'pages\admin') { $count += (Get-ChildItem -Path 'pages\admin' -Filter '*.html' -ErrorAction SilentlyContinue).Count }

    if ($expected -gt 0 -and $count -ge $expected -and -not (Test-Path '.claude/_reviewed_stage3')) {
        $msg = '[자동 트리거] 3단계 HTML ' + $count + '/' + $expected + '개 작성 완료 (02_PAGE.md 기준). 순서: (1) linter sub-agent(haiku)로 기계적 검사 → 위반 수정, (2) reviewer 호출해 3단계 전체 검토 → 블로커 해소 + 권고 반영, (3) New-Item -Path ".claude/_reviewed_stage3" -ItemType File -Force 로 마커 생성. 이미 이 절차를 진행 중이면 이 메시지는 무시.' + $caveat
    }
}
elseif ($p -match '(^|[\\/])docs[\\/]index\.html$') {
    $msg = '[자동 트리거] 고객 공유 문서(docs/index.html)가 작성됐다. 내용이 01_FEAT/02_PAGE/pages와 일치하는지 훑은 뒤 New-Item -Path ".claude/_docs_done" -ItemType File -Force 로 마커를 생성하고, 사용자에게 최종 완료 보고를 하라 (만든 파일 수 / reviewer 통과 여부 / 남은 권고).' + $caveat
}

if ($msg) {
    $out = @{
        hookSpecificOutput = @{
            hookEventName     = 'PostToolUse'
            additionalContext = $msg
        }
    } | ConvertTo-Json -Depth 5 -Compress
    Write-Output $out
}
