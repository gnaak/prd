---
description: 기획서(계약서) PDF → 기능정의 → 페이지맵 → HTML 시안 → 고객 문서까지 전 파이프라인 자율 실행 (autopilot)
---

지금부터 `AGENT.md`의 자율 워크플로우를 **autopilot 모드**로 사용자 개입 없이 끝까지 실행한다.
**단일 프로젝트(flat) 구조**다 — 기획서 PDF는 `contract/`에, 산출물은 repo 루트(`01_FEAT.md`, `02_PAGE.md`, `pages/`, `docs/`)에 생성된다.

## 0. 입력 확인 (가장 먼저)

- `contract/`에 PDF가 있는지 확인한다. **없으면**: 마커를 제거(`Remove-Item ".claude/_autopilot" -ErrorAction SilentlyContinue`)하고 사용자에게 `contract/`에 기획서 PDF를 넣어달라고 안내 후 종료.
- PDF가 여러 개면 가장 최근 파일을 대상으로 한다.

## 1. 준비 (PowerShell 한 번에 실행)

```powershell
New-Item -Path ".claude/_autopilot" -ItemType File -Force | Out-Null
Remove-Item -Path ".claude/_reviewed_stage1",".claude/_reviewed_stage2",".claude/_reviewed_stage3",".claude/_docs_done",".claude/_autopilot_count",".claude/_autopilot_stage" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "01_FEAT.md","02_PAGE.md" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "pages/user","pages/admin","pages/index.html" -Recurse -Force -ErrorAction SilentlyContinue
```

- `_autopilot` 마커가 있는 동안 Stop hook이 파이프라인 완료 전 턴 종료를 차단한다.
- 이전 빌드의 검토 마커와 **단계 산출물(01_FEAT/02_PAGE/pages의 사용자·관리자 페이지 + 허브 index.html)을 리셋**한다 — 이전 페이지가 남아 있으면 훅의 게이트가 오판한다. 특히 **exemplar(user/admin 페이지)와 허브를 같이 지워야** Stop hook의 foundation 판정(`hasFoundation`)이 false로 떨어져 ui-foundation이 다시 돈다. `common.css`·`docs/index.html`은 새로 작성되거나 유지되므로 지우지 않는다 (common.css는 ui-foundation이 갱신).
- `/build`는 항상 처음부터 다시 실행이다. 중단된 파이프라인을 이어가려면 `/build` 대신 채팅으로 진행 신호만 주면 된다 (Stop hook이 디스크 상태로 남은 단계를 안다).

## 2. 파이프라인 (AGENT.md 절차 그대로)

각 단계의 **생성은 반드시 전담 sub-agent에 위임**하고, 단계마다 reviewer 게이트를 통과한 뒤 검토 마커를 생성한다:

1. `feat-writer` → `01_FEAT.md` → reviewer → `_reviewed_stage1`
2. `page-mapper` → `02_PAGE.md` (파일 컬럼 필수) → reviewer → `_reviewed_stage2`
3. `ui-foundation` → 기반 4파일 (각 파일 바이트 검증 후) → `html-builder` 병렬 fan-out → `linter` → reviewer → `_reviewed_stage3`
4. `docs-builder` → `docs/index.html` → `_docs_done`

## 3. autopilot 규칙

- **사용자에게 스코프 확인 질문을 하지 않는다.** 해석이 갈리는 범위는 보수적으로(양쪽 다) 포함하고, 최종 보고에 "해석 포인트"로 명시한다.
- 기존 산출물이 남아 있으면 새 계약서 기준으로 덮어쓴다.
- reviewer가 같은 단계에서 블로커를 2회 연속 보고하면: 상황 보고 + `Remove-Item ".claude/_autopilot"` 후 중단.

## 4. 완료 보고

전 단계 완료 후 사용자에게: 프로젝트명, 기능/페이지/파일 수, reviewer 통과 여부, 스코프 해석 포인트, 남은 권고 사항을 보고한다. (`_autopilot` 마커는 Stop hook이 완료를 확인하고 스스로 거둔다.)
