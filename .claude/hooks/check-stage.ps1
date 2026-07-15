# PostToolUse hook (Write|Edit) — 단계 산출물 작성 감지 → reviewer 호출 reminder 인젝트 + 검토 마커 무효화
# 단일 프로젝트(flat) 구조: repo 루트의 01_FEAT.md / 02_PAGE.md / pages/ / docs/ 를 기준으로 판정한다
# Claude harness가 stdin으로 tool 호출 정보를 JSON으로 보낸다
#
# 참고: 이 훅은 "편의 트리거"다. 진행을 강제하는 백본은 Stop 훅(autopilot-gate.ps1)이며,
#       그쪽은 매 턴 디스크 상태에서 다음 단계를 재계산한다. 이 훅이 못 떠도 파이프라인은 멈추지 않는다.
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

# 빈 <html></html> 스텁이나 common.css 미import 페이지는 미완성으로 본다 (Stop hook과 동일 기준)
function Test-PageComplete([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    if ((Get-Item $path).Length -lt 400) { return $false }
    return ((Get-Content $path -Raw) -match 'assets/css/common\.css')
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
    if (Test-Path '.claude/_reviewed_stage3') {
        # 3단계 검토가 끝난 뒤 페이지가 수정됨 → 그 검토는 stale. 하위 마커 무효화하고 재검토 지시.
        Remove-Markers @('_reviewed_stage3', '_docs_done')
        $msg = '[자동 트리거] 3단계 검토(_reviewed_stage3) 이후 페이지(' + (Split-Path $p -Leaf) + ')가 수정됐다. 그 검토는 무효화됐다. (1) linter로 다시 기계검사 → 위반 수정, (2) reviewer로 재검토 → 반영, (3) New-Item -Path ".claude/_reviewed_stage3" -ItemType File -Force 로 마커 재생성.' + $caveat
    }
    else {
        # 양산 단계: 02_PAGE.md '파일' 컬럼을 source of truth로 — 기대 파일이 전부 "완성"됐을 때만 검토 안내
        $expectedFiles = @()
        if (Test-Path '02_PAGE.md') {
            $content = Get-Content '02_PAGE.md' -Raw
            $expectedFiles = @([regex]::Matches($content, '(user|admin)/[A-Za-z0-9_\-]+\.html') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        }
        $expected = $expectedFiles.Count
        $incomplete = @($expectedFiles | Where-Object { -not (Test-PageComplete "pages/$_") })

        if ($expected -gt 0 -and $incomplete.Count -eq 0) {
            $msg = '[자동 트리거] 3단계 HTML ' + $expected + '개 전부 완성 (빈 스텁 없음, common.css import 확인 — 02_PAGE.md 파일 컬럼 기준). 순서: (1) linter sub-agent(haiku)로 기계적 검사 → 위반 수정, (2) reviewer 호출해 3단계 전체 검토 → 블로커 해소 + 권고 반영, (3) New-Item -Path ".claude/_reviewed_stage3" -ItemType File -Force 로 마커 생성. 이미 이 절차를 진행 중이면 이 메시지는 무시.' + $caveat
        }
    }
}
elseif ($p -match '(^|[\\/])docs[\\/]index\.html$') {
    if (-not (Test-Path '.claude/_docs_done')) {
        $msg = '[자동 트리거] 고객 공유 문서(docs/index.html)가 작성됐다. 내용이 01_FEAT/02_PAGE/pages와 일치하는지 훑은 뒤, New-Item -Path ".claude/_docs_done" -ItemType File -Force 로 마커를 생성하고, 사용자에게 최종 완료 보고를 하라 (만든 파일 수 / reviewer 통과 여부 / 남은 권고).' + $caveat
    }
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
