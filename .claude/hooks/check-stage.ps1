# PostToolUse hook — 단계 산출물 작성 시 reviewer 호출 reminder를 인젝트
# Claude harness가 stdin으로 tool 호출 정보를 JSON으로 보낸다

$d = [Console]::In.ReadToEnd() | ConvertFrom-Json
$p = $d.tool_input.file_path
$msg = ''

if ($p -match '01_FEAT\.md$') {
    $msg = '[자동 트리거] 1단계 산출물(01_FEAT.md)이 작성됐다. 지금 즉시 Task tool로 `general-purpose` agent를 호출해 `.claude/agents/reviewer.md` 룰을 그대로 적용해 1단계 검토받아라. AGENT.md 자율 워크플로우에 따라 자가 검토 금지.'
}
elseif ($p -match '02_PAGE\.md$') {
    $msg = '[자동 트리거] 2단계 산출물(02_PAGE.md)이 작성됐다. 지금 즉시 reviewer 호출해 2단계 검토받아라.'
}
elseif ($p -match 'pages[\\/](user|admin)[\\/].*\.html$') {
    # 02_PAGE.md를 source of truth로 — 표에서 P\d+ 패턴 카운트
    $expected = 0
    if (Test-Path '02_PAGE.md') {
        $content = Get-Content '02_PAGE.md' -Raw
        $expected = ([regex]::Matches($content, '\|\s*P\d+\s*\|')).Count
    }

    # 실제 작성된 .html 카운트
    $userDir = 'pages\user'
    $adminDir = 'pages\admin'
    $count = 0
    if (Test-Path $userDir) { $count += (Get-ChildItem -Path $userDir -Filter '*.html' -ErrorAction SilentlyContinue).Count }
    if (Test-Path $adminDir) { $count += (Get-ChildItem -Path $adminDir -Filter '*.html' -ErrorAction SilentlyContinue).Count }

    if ($expected -gt 0 -and $count -ge $expected) {
        $marker = '.claude\_reviewed_stage3'
        if (-not (Test-Path $marker)) {
            $msg = "[자동 트리거] 3단계 HTML ${count}/${expected}개 작성 완료 (02_PAGE.md 기준). 지금 즉시 reviewer 호출해 3단계 전체 검토받아라. 검토가 끝나면 New-Item '.claude\_reviewed_stage3' -ItemType File -Force 로 마커 생성해 중복 호출 방지."
        }
    }
}

if ($msg) {
    $out = @{
        hookSpecificOutput = @{
            hookEventName = 'PostToolUse'
            additionalContext = $msg
        }
    } | ConvertTo-Json -Depth 5 -Compress
    Write-Output $out
}
