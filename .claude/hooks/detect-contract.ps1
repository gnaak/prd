# UserPromptSubmit hook — _inbox에 새 계약서가 있거나 미완성 고객사 폴더가 있으면 파이프라인 시작을 안내하는 컨텍스트 인젝트
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$null = [Console]::In.ReadToEnd()  # stdin 소비 (prompt 내용은 쓰지 않음)
$msg = ''

if (Test-Path '.claude/_autopilot') {
    $client = ''
    if (Test-Path '.claude/_current_client') { $client = (Get-Content '.claude/_current_client' -Raw).Trim() }
    $msg = "[컨텍스트] autopilot 파이프라인이 진행 중이다 (현재 고객사: $client). 사용자 요청을 처리하되, 사용자가 중단을 원하는 게 아니라면 AGENT.md 파이프라인을 이어서 완료하라. 사용자가 중단을 원하면 Remove-Item `".claude/_autopilot`" 실행 후 멈춰라."
}
else {
    # 1) _inbox에 아직 분류되지 않은 새 계약서
    $inbox = @(Get-ChildItem -Path 'html/_inbox' -Filter '*.pdf' -ErrorAction SilentlyContinue)
    # 2) 계약서는 있으나 01_FEAT.md가 없는 기존 고객사 폴더
    $pending = @()
    if (Test-Path 'html/clients') {
        $pending = @(Get-ChildItem -Path 'html/clients' -Directory -ErrorAction SilentlyContinue | Where-Object {
            (@(Get-ChildItem -Path (Join-Path $_.FullName 'contract') -Filter '*.pdf' -ErrorAction SilentlyContinue)).Count -gt 0 -and
            -not (Test-Path (Join-Path $_.FullName '01_FEAT.md'))
        })
    }

    if ($inbox.Count -gt 0) {
        $names = ($inbox | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
        $msg = "[컨텍스트] html/_inbox/에 아직 분류되지 않은 계약서 PDF가 있다 (감지: $names). 사용자가 진행 신호(`"ㄱㄱ`", `"시작`", `"go`", `"진행`" 등)를 주거나 이 계약서 작업을 요청하면, /build 절차(0단계 client-init으로 고객사 식별 → 1→2→3단계 → docs, 각 단계 reviewer 검토)를 시작하라. 시작할 땐 먼저 .claude/_autopilot 마커를 생성할 것."
    }
    elseif ($pending.Count -gt 0) {
        $slugs = ($pending | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
        $msg = "[컨텍스트] 계약서는 있으나 1단계 산출물(01_FEAT.md)이 없는 고객사 폴더가 있다 (감지: $slugs). 사용자가 진행 신호를 주면, 해당 고객사 slug를 .claude/_current_client에 기록하고 AGENT.md 파이프라인을 이어서 시작하라."
    }
}

if ($msg) {
    $out = @{
        hookSpecificOutput = @{
            hookEventName     = 'UserPromptSubmit'
            additionalContext = $msg
        }
    } | ConvertTo-Json -Depth 5 -Compress
    Write-Output $out
}
