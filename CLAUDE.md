# 작업 지침: 계약서 → HTML 화면 정의

이 문서는 이 repo의 **계약서 → HTML 화면정의 파이프라인**(`html/` 영역) 작업 지침이다.
**SI 개발 계약서를 받아 화면 HTML 목업까지 뽑는다.** 새 계약서는 `html/_inbox/`에 넣고, 산출물은 **고객사별 폴더 `html/clients/{slug}/`** 안에 쌓인다. (이 repo는 추후 이 산출물을 로그인 뒤에서 서빙·코멘트받는 백엔드/프론트 포털로 확장된다 — 폴더 `{slug}`가 그대로 테넌트 키가 된다.)

새 계약서가 들어오면 **0단계(고객사 식별) → 1~3단계** 프로세스를 따른다.

---

## 핵심 원칙

- 계약서의 **금액·법적 조항·기간 등은 무시**한다. 오직 "무엇을 개발해야 하는가"만 본다.
- 계약서마다 1단계 인풋만 바뀔 뿐, **2·3단계 템플릿은 그대로 재사용**한다.
- 각 단계의 산출물을 다음 단계에서 인풋으로 쓴다. 단계를 건너뛰지 않는다.
- **별도의 화면 정의서(.md)는 만들지 않는다.** HTML 자체가 화면 정의 역할을 한다.
- **모든 산출물은 해당 고객사 폴더 `html/clients/{slug}/` 안에 만든다** (이하 `$base`로 표기).

---

## 0단계: 고객사 식별 (Client Setup)

`html/_inbox/`의 새 계약서에서 **발주처(고객사)명·사업명**만 읽어 slug를 정하고 신원 메타를 만든다. (`client-init` 에이전트 담당)

### 산출물: `$base/client.json`

```json
{ "slug": "modulounge", "name": "모두라운지", "project": "맞춤형 AI 프로젝트", "contract": "contract/...pdf", "status": "building", "created": "2026-06-30" }
```

- slug = 소문자 ascii kebab-case (한글명은 로마자 음차). 폴더명이자 미래 DB Org 키
- `status` = `building`(작업 중) → 완료 시 main이 `delivered`로 변경
- `created` = 빌드 시작일 `YYYY-MM-DD` (client-init이 호출 프롬프트에 받은 오늘 날짜로 기록. 모르면 빈 문자열로 두고 main이 셋업 때 채움)
- 이후 main이 PDF를 `$base/contract/`로 옮기고(`Move-Item`) `.claude/_current_client`에 slug를 기록한 뒤 1단계로

---

## 1단계: 기능 정의 (Feature Definition)

계약서에서 **개발 범위 / 기능 리스트 / 별첨**만 읽고, 기능을 동작 단위로 쪼갠다.

### 산출물: `$base/01_FEAT.md`

**표 + 상세 섹션** 구조로 작성한다 (노션 DB로 옮길 수 있도록).

#### 표 (한 기능 = 한 행)

| ID | 기능명 | 타겟 | 카테고리 | 설명 | 관련 데이터 |
|----|--------|------|----------|------|------------|
| F1 | ... | 사용자/관리자/시스템 | 대화/분석/정보/관리 등 | 한 줄 요약 | 입력/출력/저장 정보 |

- 표 셀 안에는 **줄바꿈을 쓰지 않는다** (노션 DB import 호환)
- 카테고리는 묶음 단위(대화/분석/정보/리포트/관리 등)로 일관성 있게 부여

#### 표 아래 - 기능별 핵심 동작

```
### F1. [기능명] - 핵심 동작
- 동작 1
- 동작 2
```

핵심 동작은 표 밖에 글머리표로 분리한다. 이렇게 하면 표는 깔끔하게 DB로 옮기고, 동작은 자유롭게 편집할 수 있다.

### 체크포인트
- 계약서 원문을 그대로 옮기지 말고 **동작 단위**로 분해 (예: "AI 음성 대화" → 음성 입력 / 응답 출력 / 선톡 / 개인화 학습)
- **사용자 기능과 관리자 기능은 반드시 분리**

---

## 2단계: 페이지별 분리 (Page Mapping)

추출한 기능들을 **화면(페이지) 단위**로 묶는다. 한 페이지 = 한 사용자 목적.

### 산출물: `$base/02_PAGE.md`

**표 형태**로 작성한다.

| ID | 페이지명 | 파일 | URL | 타겟 | 포함 기능 | 진입 경로 | 다음 페이지 |
|----|---------|------|-----|------|----------|----------|------------|
| P1 | ... | user/xxx.html | /xxx | 사용자/관리자 | F1, F3 | ... | ... |

- **`파일` 컬럼은 필수다** — `pages/` 기준 상대경로(`user/xxx.html` 또는 `admin/xxx.html`)로 **한 P# = 정확히 한 파일**을 적는다. 이 컬럼이 3단계 html-builder의 파일명, linter의 대조, autopilot 완료 게이트의 검증 모두에 쓰이는 single source of truth다. URL을 파일명으로 즉석 변환하지 않는다.
- 두 페이지를 한 파일로 합치거나 한 페이지를 여러 파일로 쪼개지 않는다 — 게이트가 **P#↔파일 1:1**과 각 파일의 완성도(빈 스텁 여부)를 검증한다.

표 아래에 **페이지 맵(트리 구조)**을 ASCII로 함께 첨부한다.

### 분리 기준
- 사용자 페이지와 관리자 페이지는 **절대 섞지 않는다**
- 한 페이지에 기능이 너무 많으면 분리, 너무 가벼우면 합친다
- 계약서엔 없지만 필요한 페이지(로그인/스플래시/온보딩 등)도 이 단계에서 추가

---

## 3단계: HTML 목업 제작

2단계 페이지 맵을 그대로 HTML로 옮긴다. **와이어프레임(.md, ASCII 등) 단계는 건너뛴다** — HTML 자체가 와이어프레임이자 최종 산출물.

### 폴더 구조 (고객사별)
```
html/clients/{slug}/
├── client.json         # 고객사 신원 메타 (0단계 산출물)
├── contract/           # 그 고객사 계약서 PDF
├── 01_FEAT.md  02_PAGE.md
├── docs/index.html     # 고객 공유 문서
└── pages/
    ├── index.html      # 페이지 맵 허브 (사용자/관리자 영역 시각 구분)
    ├── user/
    │   ├── home.html
    │   └── ...
    ├── admin/
    │   ├── dashboard.html
    │   └── ...
    └── assets/
        └── css/common.css
```

### 시안 미리보기
- 산출물은 정적 HTML이라 파일을 열기만 하면 된다. VS Code Live Server(설정된 포트 5501)로 **`$base/pages/index.html`**(시안 허브) 또는 **`$base/docs/index.html`**(고객 문서)를 연다.
- 페이지 간 상대경로 링크가 동작하려면 `pages/` 폴더 구조를 유지한 채 서빙해야 한다 (단일 파일만 떼어 열면 링크가 깨질 수 있음).

### 작성 원칙
- `pages/index.html`은 모든 페이지로 가는 **허브** 역할 (사용자/관리자 카드 그리드)
- 페이지 간 이동 링크는 **실제로 동작**하도록 연결
- 더미 데이터는 실제 길이·개수와 유사하게 채움
- 한 번 만든 `common.css`는 다음 고객사에도 재활용 (고객사 폴더마다 자기 사본을 가짐 — 폴더가 독립적으로 서빙되도록)
- 모바일 화면은 모바일 폭으로 시각화 (PC에서 봐도 모바일임을 알게)
- 관리자 화면은 PC 폭 활용

### 디자인 톤 — `DESIGN.md` 참조 필수
- 루트의 **`DESIGN.md`가 있으면 그 톤을 따른다** (현재 프로젝트는 Notion-inspired)
- 디자인 토큰을 그대로 옮긴 단일 `common.css`를 만들어 모든 페이지가 import
- **AI스러운 클리셰 금지**:
  - 그라데이션 CTA 배경 ❌ — 단색 fill만
  - 진한 드롭섀도 ❌ — 헤어라인 위주, 그림자는 여러 단의 near-transparent 레이어
  - 이모지 과다 사용 ❌ — 필요한 곳에만 절제해서
  - 다채로운 컬러 ❌ — primary 1개 + 텍스트 톤만, 스티커 팔레트는 장식 전용
  - 휘황찬란한 폰 프레임 노치 ❌ — 절제된 컨테이너로
- **Notion 톤 특징** (현 DESIGN.md 기준):
  - warm paper-soft canvas (`#f6f5f4`)에 흰 카드
  - 헤드라인은 weight 700 + 큰 사이즈에 **negative letter-spacing 명시적 적용**
  - 마케팅 CTA는 pill (`r-full`), 유틸리티는 8px (`r-md`), 인풋은 4px (`r-xs`)
  - 단 하나의 구조 액센트 = Primary Blue (`#0075de`) — CTA + 링크에만

### 시안 페이지 제작 디테일

- **아이콘은 Lucide** 사용 (`<script src="https://unpkg.com/lucide@latest"></script>` + `<i data-lucide="..."></i>` + `lucide.createIcons()`). 이모지·점(●○)·이미지 직접 사용 금지
- **모바일 프레임은 PC viewport에 고정**:
  - `.mobile-stage`는 `height: 100vh` + flex center → 스크롤 없이 항상 viewport 안에 fit
  - `.mobile-frame` 사이즈는 `360 × 720px` (max-height: calc(100vh - 48px))
  - 모바일 내부 스크롤은 `.m-content`에서만
- **프로덕션 수준 밀도**: 노년층 친화한답시고 폰트·버튼을 키우지 말 것
  - body 14px, 헤더 15px, h1 18~20px, 헤딩-1 22~26px 정도
  - 버튼 padding `8px 18px` (기본) / `10px 18px` (md) — 16px 폭 padding 같은 거대 버튼 ❌
  - 패딩·간격은 16/20/24px 단위, 32px 이상은 큰 섹션에만
  - 메인 액션 버튼(마이크 등)도 **48px** 정도. 60px 이상은 과함

### 버튼 variants (common.css)

| 클래스 | 용도 | 형태 |
|--------|------|------|
| `btn-primary` | 주 CTA, 1순위 액션 | 파란 pill (`#0075de` + `r-full`) |
| `btn-secondary` | 보조 CTA (hero 페어용) | 흰 pill + shadow-1 |
| `btn-outline` | 카드 안 secondary 액션 (예: 프로필 수정) | 흰 + hairline 보더 + `r-md`, padding 9×16 |
| `btn-utility` | 작은 인라인 액션 (헤더 액션, 페이지네이션) | 흰 + hairline + `r-md`, padding 4×12 |
| `btn-ghost` | 강조 최소 액션 (로그아웃 등) | 무배경, padding 9×16, hover 시 canvas |

**선택 기준**:
- 페이지에 한 번 등장하는 메인 CTA → `btn-primary`
- 카드 안에서 "수정", "추가" 같은 secondary 액션 → `btn-outline`
- "메모 추가", "공유" 같은 헤더/툴바 액션 → `btn-utility`
- "로그아웃", "취소" 같은 약한 액션 → `btn-ghost`

### 인터랙션 — 모든 버튼은 동작 필수

시안이라도 **클릭에 반응 없는 죽은 버튼은 만들지 않는다**. 최소한 다음 중 하나는 가져야 함:

- **페이지 이동**: 다른 시안으로 `onclick="location.href=..."` 또는 `<a href>`
- **상태 토글**: 탭 / 칩 / segment 컨트롤 → `active` 클래스 토글
- **시각 피드백**: 북마크 저장 (색 반전), 플레이 버튼 (▶ ↔ ⏸), 신청 완료 (텍스트 변경 + disabled), 알림 읽음 (unread 해제)
- **자동 동작**: 스플래시 1.8초 후 다음 페이지로

페이지 하단의 `<script>` 안에 `lucide.createIcons()`와 함께 인터랙션 핸들러를 묶어 둔다.

### 배경 처리 (회색 영역 꽉 채우기)

마이페이지처럼 "흰 카드 + 회색 본문" 구조를 만들 때 **회색 background는 스크롤 컨테이너 자체에 직접 적용**한다.
자식 영역(예: `.m-content`)에만 회색을 주면 그 외 빈 공간이 모바일 frame의 흰색으로 비쳐서 회색이 끊겨 보임.

```html
<!-- ✅ 옳음 -->
<div style="flex:1; overflow-y:auto; background: var(--canvas);">
  <div class="profile-head">...</div>  <!-- 흰 박스 -->
  <div class="tabs" style="background: var(--canvas);">...</div>
  <div style="padding: 16px;">...</div>
</div>
```

---

## 산출물 요약

모든 산출물은 `html/clients/{slug}/` 안에 생성된다 (이하 `$base`):

| 단계 | 파일 | 역할 |
|------|------|------|
| 0 | `$base/client.json` | 고객사 신원 메타 (slug·name·project) |
| 1 | `$base/01_FEAT.md` | 기능 카탈로그 (표) |
| 2 | `$base/02_PAGE.md` | 페이지 맵 (표 + 트리) |
| 3 | `$base/pages/**/*.html` | HTML 목업 (실제 화면 시안) |
| 공통 | `$base/docs/index.html` | **고객 공유용 인터랙티브 문서** (모든 단계 누적 반영 + 시안으로 연결) |

### 고객 공유용 산출물 (`$base/docs/index.html`)

- 1단계 산출물부터 차례로 **하나의 HTML 문서**에 누적해 채워간다
- `pages/`와는 다른 산출물 — 그건 *화면 시안*, 이건 *기획 문서*
- **시안 섹션은 `pages/`의 각 HTML로 이동하는 카드 그리드**로 구성 (ASCII 와이어프레임 ❌)
- 톤은 **비즈니스 문서** (고객사에 보낼 수 있는 수준)

#### 구조
- 좌측 사이드바 네비 + 우측 콘텐츠 (2단 그리드)
- 섹션: 1. 환경 / 2. 기능 목록 / 3. 페이지 맵 / 4. 화면 시안 (`pages/` 링크)
- 카테고리 필터, 카드 펼침 등 기본 인터랙션 포함

#### 디자인 가이드
- **레이아웃은 화면 전체 너비**를 사용한다. `max-width`로 가운데 정렬 ❌
- **사이드바 네비는 메인 섹션만** 표시. 하위 카테고리 등 sub 항목은 넣지 않는다
- 사이드바 항목 간격은 **타이트하게** (`gap: 2px`, 항목 padding `6px 12px` 기준)
- **앵커 이동 시 상단 여백** 필수 — 모든 `section`에 `scroll-margin-top: 32px` 적용
- **"진행 상황", "작업 중" 같은 내부용 UI는 넣지 않는다** — 고객은 완성본만 받음
- 폰트는 Pretendard 사용 (CDN OK)

#### 시각화 원칙
- **가볍게 유지**: 외부 라이브러리(Mermaid·D3 등)에 의존하지 않는다
- 페이지 흐름 트리는 `<pre>` + 텍스트 트리(`├─`, `└─`)로 충분
- **ASCII 와이어프레임은 docs/index.html에도 넣지 않는다** — 시안 섹션은 실제 HTML로 링크

#### 2단계(페이지 맵) 반영 시
- 페이지 카드 그리드 + 타겟(사용자/관리자) 필터 버튼
- 카드에 페이지 ID, 타겟 뱃지, 관련 기능 ID 태그(F1·F2…), URL, 설명, 다음 페이지 표시
- 그 아래에 **사용자/관리자 분리한 텍스트 트리** 2개 (좌우 배치)

#### 3단계(화면 시안) 반영 시
- 페이지별 카드 (썸네일 영역 포함)에서 클릭 시 `pages/xxx.html`로 이동 (`target="_blank"`)
- 카드에는 페이지명, ID, 타겟, 관련 기능 태그(F1·F2…), 짧은 설명만 표시
- **썸네일 톤으로 플랫폼 시각 구분**: 사용자(모바일)=청록 그라데이션, 관리자(PC)=노랑 그라데이션 (그라데이션 허용은 docs 썸네일 한정 — `pages/`의 금지 규칙과 별개)
- 썸네일은 일단 이모지(📱/🖥️)로 두고 추후 실제 스크린샷으로 교체 가능

---

## 작업 시작 시 행동

기본은 `AGENT.md`의 **자율 워크플로우**를 따른다 — main은 오케스트레이터, 산출물 생성은 전담 sub-agent에 위임하고, 매 단계 `reviewer` 검토로 자가 합리화를 방지한다.

### 실행 모드

1. **`/build` (권장)** — 사용자가 `html/_inbox/`에 PDF만 넣고 `/build` 실행. 0단계(고객사 식별)부터 1→2→3단계 + docs까지 스코프 질문 없이 전자동. 해석이 갈리는 범위는 보수적으로 포함하고 완료 보고에 명시. (기존 고객사 재빌드는 `/build {slug}`)
2. **대화 모드** — PDF 감지 후 사용자가 "ㄱㄱ"/"시작" 등 진행 신호를 주면 동일 파이프라인을 autopilot으로 진행. 시작 전 개발 범위 발췌를 한 번 보여주는 점만 다름.

어느 모드든 reviewer가 같은 단계에서 2회 연속 블로커를 보고하거나 스코프 변경이 필요할 때만 사용자에게 보고하고 멈춘다.

**`reviewer` 호출은 필수** — main이 자기(또는 sub-agent)가 만든 산출물을 직접 검토하지 않는다.

### 자동화 키트 (새 repo에 그대로 복사해서 재사용)

| 구성 요소 | 파일 | 모델 |
|---|---|---|
| 0단계 생성 (고객사 식별) | `.claude/agents/client-init.md` | sonnet |
| 1단계 생성 (계약 해석) | `.claude/agents/feat-writer.md` | opus |
| 2단계 생성 (페이지 맵) | `.claude/agents/page-mapper.md` | sonnet |
| 3단계 기반 (CSS+허브+exemplar) | `.claude/agents/ui-foundation.md` | opus |
| 3단계 양산 (페이지 1장/호출) | `.claude/agents/html-builder.md` | sonnet |
| 기계적 검사 | `.claude/agents/linter.md` | haiku |
| 단계 검토 게이트 | `.claude/agents/reviewer.md` | opus |
| 고객 문서 | `.claude/agents/docs-builder.md` | sonnet |
| 훅 (계약서 감지 / 단계 트리거 / 완주 게이트) | `.claude/hooks/*.ps1` + `.claude/settings.json` | - |
| 진입점 | `.claude/commands/build.md` (`/build`) | - |
| 오케스트레이션 룰 | `AGENT.md` | - |

**새 고객사 추가** = `html/_inbox/`에 계약서 PDF를 넣고 `/build` 실행. 0단계(client-init)가 고객사를 식별해 `html/clients/{slug}/`를 만들고 거기에 전 산출물을 쌓는다.

**자동화 키트를 새 repo로 복사**할 땐 `CLAUDE.md` + `DESIGN.md` + `AGENT.md` + `.claude/` + 빈 `html/_inbox/`만 가져가고, 기존 `html/clients/*` 산출물은 복사하지 않는다.
