# UserPromptSubmit hook — contract/에 계약서 PDF가 있는데 1단계 산출물이 없으면 파이프라인 시작을 안내하는 컨텍스트 인젝트
# 단일 프로젝트(flat) 구조: 산출물은 repo 루트 (contract/ 01_FEAT.md 02_PAGE.md pages/ docs/)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$null = [Console]::In.ReadToEnd()  # stdin 소비 (prompt 내용은 쓰지 않음)
$msg = ''

if (Test-Path '.claude/_autopilot') {
    $msg = "[컨텍스트] autopilot 파이프라인이 진행 중이다. 사용자 요청을 처리하되, 사용자가 중단을 원하는 게 아니라면 AGENT.md 파이프라인을 이어서 완료하라. 사용자가 중단을 원하면 Remove-Item `".claude/_autopilot`" 실행 후 멈춰라."
}
else {
    $pdfs = @(Get-ChildItem -Path 'contract' -Filter '*.pdf' -ErrorAction SilentlyContinue)
    if ($pdfs.Count -gt 0 -and -not (Test-Path '01_FEAT.md')) {
        $names = ($pdfs | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
        $msg = "[컨텍스트] contract/에 계약서 PDF가 있는데 1단계 산출물(01_FEAT.md)이 아직 없다 (감지: $names). 사용자가 진행 신호(`"ㄱㄱ`", `"시작`", `"go`", `"진행`" 등)를 주거나 이 계약서 작업을 요청하면 /build 절차(1→2→3단계 + docs, 각 단계 reviewer 검토)를 시작하라. 시작할 땐 먼저 .claude/_autopilot 마커를 생성할 것."
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
