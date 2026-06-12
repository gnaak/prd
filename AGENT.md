# 자율 워크플로우 (Agent Mode)

이 문서는 main agent가 **사용자 개입 없이** 계약서 PDF → HTML 시안 전 과정을 진행하기 위한 룰이다.
main은 **오케스트레이터**다 — 산출물 생성은 전담 sub-agent에 위임하고, main은 위임·검토 반영·소규모 수정만 직접 한다.

---

## 에이전트 구성과 모델 배치

| 에이전트 | 모델 | 담당 | 호출 시점 |
|---|---|---|---|
| main (오케스트레이터) | 세션 모델 | Task 위임, 검토 반영, 소규모 수정 | - |
| `feat-writer` | **opus** | 계약 PDF → `01_FEAT.md` | 1단계 |
| `page-mapper` | **sonnet** | `01_FEAT.md` → `02_PAGE.md` | 2단계 |
| `ui-foundation` | **opus** | common.css + 허브 + exemplar 2장 | 3단계 시작 |
| `html-builder` | **sonnet** | 나머지 페이지, **호출당 1장** (병렬) | 3단계 |
| `linter` | **haiku** | 기계적 검사 (read-only) | 3단계, reviewer 전 |
| `reviewer` | **opus** | 단계별 품질 게이트 (read-only) | 매 단계 후 |
| `docs-builder` | **sonnet** | 고객 공유 문서 `docs/index.html` | 마무리 |

배치 원칙: 추론이 무거운 곳(계약 해석, 디자인 기반, 검토 게이트)에 opus / 양산 작업에 sonnet / 기계적 검사에 haiku.

> ⚠️ 환경변수 `CLAUDE_CODE_SUBAGENT_MODEL`을 설정하면 위 frontmatter 모델 배치가 **전부 그 모델로 덮어써진다**. 이 키트에서는 설정 금지 (settings에서 이미 제거됨).

---

## 트리거

다음 중 하나면 이 워크플로우를 시작한다:
- 사용자가 `/build` 실행 (전자동 — 스코프 질문도 생략)
- `contract/`에 새 PDF가 있고 사용자가 "ㄱㄱ" / "시작" / "go" 등 진행 신호를 줌
- 사용자가 명시적으로 "AGENT.md 따라 진행" 요청

**시작하면 가장 먼저 autopilot 마커를 세팅한다** (Stop hook이 완주를 보장하게 됨):

```powershell
New-Item -Path ".claude/_autopilot" -ItemType File -Force | Out-Null; Remove-Item -Path ".claude/_reviewed_stage1",".claude/_reviewed_stage2",".claude/_reviewed_stage3",".claude/_docs_done",".claude/_autopilot_count" -Force -ErrorAction SilentlyContinue
```

---

## 마커 프로토콜

훅들이 이 마커로 진행 상태를 추적한다. **마커는 항상 main이 생성**한다 (reviewer 통과 + 권고 반영이 끝난 직후).

| 마커 (`.claude/`) | 의미 | 생성 주체 |
|---|---|---|
| `_autopilot` | 파이프라인 진행 중 — Stop hook이 미완료 종료를 차단 | main (시작 시) / Stop hook이 완료 시 제거 |
| `_reviewed_stage1` | 1단계 검토 통과 + 반영 완료 | main |
| `_reviewed_stage2` | 2단계 검토 통과 + 반영 완료 | main |
| `_reviewed_stage3` | 3단계 lint + 검토 통과 + 반영 완료 | main |
| `_docs_done` | docs/index.html 완료 | main |
| `_autopilot_count` | Stop hook 차단 횟수 카운터 (상한 20 — 도달 시 hook이 autopilot 강제 해제) | Stop hook이 관리 |

산출물이 다시 수정되면 PostToolUse hook이 **그 단계를 포함한 이후 단계의 검토 마커를 전부 제거**한다 (예: 01_FEAT.md 수정 → `_reviewed_stage1/2/3` + `_docs_done` 제거) — 수정했으면 재검토가 원칙.

---

## 루프 구조

```
[autopilot 마커 세팅]
   ↓
[1단계] feat-writer(opus) → 01_FEAT.md
   ↓  reviewer(opus) 검토
   ├─ ✅ Pass + ⚠️만 → main이 권고 반영 → _reviewed_stage1 생성
   ├─ ❌ 블로커 → 소규모면 main이 수정 / 구조적이면 feat-writer에 punch list 넘겨 재작성 → 재검토 (최대 2회)
   └─ 2회 연속 블로커 → 사용자 보고 + _autopilot 제거 후 중단
   ↓
[2단계] page-mapper(sonnet) → 02_PAGE.md → reviewer → _reviewed_stage2
   ↓
[3단계] ui-foundation(opus) → common.css + pages/index.html + exemplar 2장
   ↓
   html-builder(sonnet) 병렬 fan-out — 남은 페이지 전부, 호출당 1장
   ↓
   linter(haiku) → 위반은 main이 직접 수정
   ↓
   reviewer(opus) 3단계 전체 검토 → 반영 → _reviewed_stage3
   ↓
[마무리] docs-builder(sonnet) → docs/index.html → _docs_done
   ↓
[최종 완료 보고] (Stop hook이 완료 확인 후 _autopilot 자동 제거)
```

---

## 단계별 실행 디테일

### 1단계: 기능 정의

```
Task(subagent_type="feat-writer",
     prompt="contract/[파일명].pdf 로 1단계 진행. 01_FEAT.md 작성.")
```

- feat-writer가 반환한 "스코프 발췌 요약"과 "해석 포인트"는 기억해 뒀다 최종 보고에 포함
- reviewer 검토 → 반영 → `_reviewed_stage1`

### 2단계: 페이지 매핑

```
Task(subagent_type="page-mapper", prompt="01_FEAT.md 기반으로 2단계 진행. 02_PAGE.md 작성.")
```

- reviewer 검토 → 반영 → `_reviewed_stage2`

### 3단계: HTML 시안

1. **기반 먼저** — `Task(subagent_type="ui-foundation", prompt="3단계 기반 작업. common.css + pages/index.html 허브 + exemplar 사용자 1장(홈) + 관리자 1장(대시보드).")`
2. ui-foundation이 반환한 exemplar 경로·컴포넌트 카탈로그를 받아, **남은 페이지를 html-builder로 병렬 fan-out** — 한 메시지에 Task 4~6개씩, 페이지당 1호출:
   ```
   Task(subagent_type="html-builder",
        prompt="P7 알림 (pages/user/notifications.html) 제작.
                exemplar: pages/user/home.html (공통 크롬 그대로 복사).
                02_PAGE.md의 P7 행과 01_FEAT.md의 F7 참고.")
   ```
3. 전부 완료되면 `Task(subagent_type="linter", prompt="pages/ 전체 lint.")` → **위반 항목은 main이 직접 수정** (builder 재호출은 구조적 문제일 때만)
4. `reviewer` 3단계 검토 → 반영 → `_reviewed_stage3`

### 마무리

1. `Task(subagent_type="docs-builder", prompt="docs/index.html 생성/갱신. 01_FEAT + 02_PAGE + pages/ 전체 반영.")`
2. 결과 확인 → `_docs_done` 마커 생성
3. **최종 완료 보고**: 기능/페이지/파일 수, reviewer 통과 여부, 스코프 해석 포인트, 남은 ⚠️ 권고

---

## 검토 게이트 규칙

- **reviewer 호출은 반드시 Task tool** (subagent_type="reviewer"), 프롬프트에 단계와 대상 파일 명시
- main은 자기(또는 sub-agent)가 만든 산출물을 직접 "통과" 판정하지 않는다 — 반드시 reviewer를 거친다
- ⚠️ 권고도 가능한 반영한다. 반영하지 않기로 한 권고는 최종 보고에 사유와 함께 남긴다
- reviewer 결과 원문을 사용자에게 그대로 붙이지 않는다 — **무엇을 고쳤는지**만 요약
- 같은 단계 재검토는 최대 2회. 2회 연속 블로커면: 사용자 보고 + `Remove-Item ".claude/_autopilot"` 후 중단

## 사용자 개입 정책

기본은 무개입 완주. 다음 경우에만 멈추고 사용자에게 보고한다:
- reviewer가 같은 단계에서 2회 연속 블로커
- 계약서 해석이 갈려 **산출물 구조가 통째로 달라지는** 경우 (단순 포함/제외는 보수적으로 포함하고 보고에 명시)
- 사용자가 중단 요청 → `Remove-Item ".claude/_autopilot"` 후 종료

## sub-agent 운용 메모

- sub-agent는 Task tool이 없다 — 훅 메시지에 "reviewer를 호출하라"가 떠도 그건 main 전용 지시다 (훅 메시지에 명시되어 있음)
- html-builder fan-out 중 일부가 실패(null)하면 해당 페이지만 재호출
- 모든 sub-agent는 자기 산출물 경로를 반환한다 — main은 반환값으로 진행 상태를 추적하고, 파일 존재를 Glob으로 재확인한다
