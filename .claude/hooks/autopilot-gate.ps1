# Stop hook — autopilot 모드(.claude/_autopilot 존재)에서 파이프라인이 미완료면 턴 종료를 막고 다음 단계를 지시
# 고객사별 구조: .claude/_current_client 의 slug로 html/clients/{slug}/ 를 대상으로 판정한다
# 안전장치: "같은 단계에서 진전 없이 막힌 연속 횟수"가 상한(STALL_CAP)에 도달하면 마커를 거두고
#           무조건 종료 허용 (무한 루프 방지). 단계가 바뀌면(=진전) 카운터는 0으로 리셋되므로
#           페이지가 많거나 reviewer 재검토가 길어도 정상 진행이면 카운터가 누적되지 않는다.
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

# ---- 현재 고객사 base 경로 ----
$slug = ''
if (Test-Path '.claude/_current_client') { $slug = (Get-Content '.claude/_current_client' -Raw).Trim() }
$base = ''
if ($slug) { $base = "html/clients/$slug" }

# ---- 마커 정합성 가드 ----
# _current_client가 가리키는 폴더가 없으면 이전 빌드의 검토 마커는 신뢰할 수 없다 → 무효화.
if ((-not $slug) -or (-not (Test-Path $base))) {
    Remove-Item '.claude/_reviewed_stage1', '.claude/_reviewed_stage2', '.claude/_reviewed_stage3', '.claude/_docs_done' -Force -ErrorAction SilentlyContinue
}

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
    # ----- 3단계: 02_PAGE.md의 '파일' 컬럼을 기준으로 P#↔파일 1:1 + 각 파일의 완성도를 검증 -----
    # 기대 파일 집합 = 표에 적힌 user/xxx.html · admin/xxx.html 토큰 (URL엔 .html이 없어 오검출 없음)
    $expectedFiles = @()
    if (Test-Path "$base/02_PAGE.md") {
        $content = Get-Content "$base/02_PAGE.md" -Raw
        $expectedFiles = @([regex]::Matches($content, '(user|admin)/[A-Za-z0-9_\-]+\.html') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    }
    $expected = $expectedFiles.Count

    # 미완성 = 기대 파일 중 없거나 / 빈 스텁이거나 / common.css 미import (개수가 아니라 내용으로 판정)
    $incomplete = @($expectedFiles | Where-Object { -not (Test-PageComplete "$base/pages/$_") })
    $done = $expected - $incomplete.Count

    # 고아 = 디스크에 있으나 표에 없는 user/admin 페이지 (드리프트 감지)
    $actualRel = @()
    foreach ($d in 'user', 'admin') {
        if (Test-Path "$base/pages/$d") {
            Get-ChildItem "$base/pages/$d" -Filter '*.html' -ErrorAction SilentlyContinue | ForEach-Object { $actualRel += "$d/$($_.Name)" }
        }
    }
    $orphans = @($actualRel | Where-Object { $expectedFiles -notcontains $_ })

    # foundation = css + 허브 + 사용자 exemplar 1장 + 관리자 exemplar 1장이 모두 존재 (재빌드 시 exemplar 누락 방지)
    $hasFoundation = (Test-Path "$base/pages/assets/css/common.css") -and (Test-Path "$base/pages/index.html") -and `
    (@(Get-ChildItem "$base/pages/user" -Filter '*.html' -ErrorAction SilentlyContinue).Count -gt 0) -and `
    (@(Get-ChildItem "$base/pages/admin" -Filter '*.html' -ErrorAction SilentlyContinue).Count -gt 0)

    if ($expected -eq 0) {
        $stage = 'page-files'
        $next = "$base/02_PAGE.md 페이지 목록 표에 '파일' 컬럼(user/xxx.html · admin/xxx.html)이 없다. Task(subagent_type=`"page-mapper`")로 표를 갱신해 모든 P#에 파일 칸을 채워라 — 완료 게이트가 이 컬럼으로 페이지 완성도를 검증한다."
    }
    elseif (-not $hasFoundation) {
        $stage = 'foundation'
        $next = "3단계 기반: Task(subagent_type=`"ui-foundation`")로 $base/pages/assets/css/common.css + $base/pages/index.html 허브 + 사용자/관리자 exemplar 페이지를 생성하라. exemplar(홈/대시보드)가 빈 <html></html> 스텁이면 안 된다 — 반환 전 각 파일을 Read로 확인하라."
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
        $next = "3단계 검토: (1) Task(subagent_type=`"linter`")로 $base/pages/ 기계적 검사 → 위반(빈 파일/깨진 링크 포함) 수정, (2) reviewer로 전체 검토 → 반영, (3) `".claude/_reviewed_stage3`" 마커 생성. (전 페이지가 비어있지 않고 common.css를 import함은 게이트가 이미 보장한다.)"
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

$reason = "[autopilot $stage $n/$cap] 파이프라인이 아직 끝나지 않았다 (고객사: $slug). 다음 단계를 지금 실행하라 → $next 단, reviewer가 같은 단계에서 블로커를 2회 연속 보고했거나 사용자에게 물어야만 하는 상황이면: 상황을 보고하고 Remove-Item `".claude/_autopilot`" 실행 후 종료하라."

$out = @{
    decision = 'block'
    reason   = $reason
} | ConvertTo-Json -Depth 3 -Compress
Write-Output $out
