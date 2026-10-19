# Design PRD — Constellate v1.0
**코드가 주인공, 환경은 무대**

- 작성일: 2026-10-18 · 갱신: 2026-10-19 (Blender 파이프라인 실제 스크립트·렌더 파일명, floorGrid 규칙 포함, Band0…Band3 슬롯 반영)
- 작성자: 김민웅(콜슨) · GitHub `kimminung`
- 기준: `Docs/VISION.md` v0.1 · `Docs/PRD-Tech-Constellate.md` v1.0 (FR-7 테마, FR-3 오브, FR-8 플랫폼 UI) · `Blender/scripts/README.md`
- 색 값의 단일 소스: `ConstellateKit/Sources/ConstellateKit/Theme/ConstellateTheme.swift`. 이 문서의 hex는 그 코드로 계산한 값이다.
- 에셋 파이프라인: Blender 5.2 헤드리스(`/Applications/Blender.app`) → `Constellate/Resources/Assets3D/*.usdz`, `Resources/Textures/*.png`, `Blender/renders/*.png`

---

## 1. 디자인 원칙

| # | 원칙 | 뜻 | 구현 규칙 |
|---|---|---|---|
| D1 | **코드가 주인공** | 공간에서 가장 밝고 선명한 것은 항상 코드 글자다 | 코드 팔레트 chroma ≥ 0.35, L ≥ 0.62; 카드 배경 대비 ≥ 4.5:1 |
| D2 | **환경은 무대** | 하늘·바닥·안개·에셋은 어둡고 탁해서 뒤로 물러난다 | 환경 chroma ≤ 0.16, L ≤ 0.30; 발광은 테마 헤일로 색 하나만 |
| D3 | **규칙 기반 색** | 색은 손으로 고르지 않고 규칙으로 생성·검증한다 | `ConstellateTheme.tinted(hue:)` + `validate()` + `ThemeTests` |
| D4 | **구조가 곧 레이아웃** | 위치·크기는 코드 트리/그래프에서만 나온다(장식 좌표 없음) | `ConstellationLayoutEngine` 결정적 배치 |
| D5 | **연속, 스냅 없음** | 다이얼·dock·expand는 연속 함수와 보간 | 투영 선형, 전환 0.6 s 이징 |
| D6 | **존재감은 에너지로** | 오브 상태는 색이 아니라 에너지(발광·속도·방출률)로 말한다 | Presence 0.22 / 0.55 / 1.0 / 0.75 |

---

## 2. 색 체계

### 2.1 코드 팔레트 (`CodePalette.standard`, 고정, 코드 전용)

| 역할 | hex | hue | chroma | L | vs 카드 배경 대비 |
|---|---|---|---|---|---|
| plain | `#F4F6FB` | 223° | 0.03 | 0.97 | 17.3 |
| keyword | `#FF7AB6` | 333° | 0.52 | 0.74 | 7.7 |
| type | `#5EE1FF` | 191° | 0.63 | 0.68 | 12.2 |
| function | `#FFD166` | 42° | 0.60 | 0.70 | 12.9 |
| string | `#B8FF7A` | 92° | 0.52 | 0.74 | 15.7 |
| number | `#B89CFF` | 257° | 0.39 | 0.81 | 8.2 |
| comment | `#8A93A6` | 221° | 0.11 | 0.60 | 6.0 (규칙 비대상) |
| cardBackground | `#0E1220 @ 78 %` | — | — | — | — |
| cardBorder | `#FFFFFF @ 14 %` | — | — | — | — |

예약 hue(환경이 피해야 하는 값) = **333°, 191°, 42°, 92°, 257°**.

### 2.2 환경 팔레트 — Dark (`ConstellateTheme.dark`)

| 역할 | hex | 비고 |
|---|---|---|
| skyTop | `#05070F` | chroma 0.04, L 0.04 |
| skyHorizon | `#121733` | chroma 0.13, L 0.14, hue 231° — plain 대비 16.2 |
| skyBottom | `#0A0B14` | |
| floor | `#0B0E1A` | |
| floorGrid | `#2A3150 @ 55 %` | |
| fog | `#0B0F1F` | 다이어그램 배경색으로도 사용 |
| orbHalo | `#9B8CFF` | 호스트 오브 헤일로 |
| orbBands | `#7F7CFF` `#58D7E8` `#FF8FD1` `#FFFFFF` | 밴드 4 |
| avatarAccent | `#6FB6FF` | 참가자 기본 액센트(+ hueOffset) |
| beacon | `#FFD166` | 비콘(코드 function과 같은 앰버 — 의도적: "찾은 코드"를 가리키는 색) |
| highlight | `#5EE1FF` | AI가 찾은 노드 링 |
| edgeContains | `#6B7390 @ 55 %` | 트리 엣지 |
| edgeImports | `#58D7E8 @ 70 %` | |
| edgeReferences | `#FF8FD1 @ 70 %` | |
| edgeInherits | `#C9B6FF @ 80 %` | |
| edgeCalls | `#FFD166 @ 70 %` | |

레이어 밴드: presentation `#5EE1FF` cyan · domain `#C9B6FF` lavender · data `#FFD166` amber · infrastructure `#8A93A6` grey · test `#B8FF7A` lime · unknown `#A7ADBF`.

### 2.3 Tinted 생성식 (`ConstellateTheme.tinted(hue:)`)

입력 hue `H₀`를 먼저 `safeEnvironmentHue(H₀, avoiding: 예약 hue, minDistance: 22)`로 보정해 `H`를 얻는다(예약 hue와 22° 미만이면 가까운 쪽으로 22°까지 밀어냄). 그 다음:

| 역할 | 식 (HSL) |
|---|---|
| skyTop | `HSL(H, 0.30, 0.06)` |
| skyHorizon | `HSL(H, 0.34, 0.17)` |
| skyBottom | `HSL(H, 0.28, 0.07)` |
| floor | `HSL(H, 0.22, 0.08)` |
| floorGrid | `HSL(H, 0.26, 0.28) @ 55 %` (chroma 0.146 — 규칙 0.16 안) |
| fog | `HSL(H, 0.30, 0.10)` |
| orbHalo | `HSL(H, 0.75, 0.72)` |
| orbBands | `HSL(H, 0.8, 0.7)`, `HSL(H+40, 0.7, 0.7)`, `HSL(H−40, 0.7, 0.72)`, `#FFFFFF` |
| avatarAccent | `HSL(H+180, 0.6, 0.68)` |
| 나머지(beacon·highlight·edge·layerBands·code) | Dark와 동일 |

**프리셋 계산값** (코드와 동일한 HSL 변환으로 산출):

| 프리셋 | 입력 H₀ | 실효 H | skyTop | skyHorizon | floor | fog | orbHalo | avatarAccent | plain/skyHorizon 대비 |
|---|---|---|---|---|---|---|---|---|---|
| Dark | — | — | `#05070F` | `#121733` | `#0B0E1A` | `#0B0F1F` | `#9B8CFF` | `#6FB6FF` | 16.2 |
| Ocean | 210° | **213.2°** (191°+22°) | `#0B0F14` | `#1D2A3A` | `#101419` | `#121921` | `#82B2ED` | `#DEB37C` | 13.5 |
| Moss | 150° | 150° | `#0B140F` | `#1D3A2B` | `#101914` | `#12211A` | `#82EDB8` | `#DE7CAD` | 11.5 |
| Ember | 20° | 20° (42°와 정확히 22° 거리) | `#140E0B` | `#3A261D` | `#191310` | `#211712` | `#EDA682` | `#7CBEDE` | 13.1 |
| Nebula | 275° | **279°** (257°+22°) | `#110B14` | `#301D3A` | `#161019` | `#1C1221` | `#C882ED` | `#9FDE7C` | 14.3 |

밴드 색(참고): Ocean `#75ACF0 #947DE8 #86EADE` · Moss `#75F0B3 #7DD6E8 #96EA86` · Ember `#F09E75 #E8E87D #EA86A7` · Nebula `#C575F0 #E87DC6 #8687EA` (+ 흰색).
floorGrid(S 0.26): Ocean `#35455A` · Moss `#355A47` · Ember `#5A4135` · Nebula `#4D355A` (모두 @ 55 %, chroma 0.146).

> Ocean과 Nebula는 사용자가 고른 hue 그대로가 아니라 자동 회피된 hue로 렌더된다. `ThemeMode.tinted(hue:)`에는 원래 입력(210, 275)이 보존되므로 UI의 hue 슬라이더는 입력값을 보여주고, 미리보기 스와치만 실효 색을 보여준다.

### 2.4 대비 · 회피 규칙 (`validate()`)

| 규칙 ID | 대상 | 조건 | 이유 |
|---|---|---|---|
| env.chroma | skyTop·skyHorizon·skyBottom·floor·floorGrid·fog | chroma(max−min 채널) **≤ 0.16** | 환경이 "색"으로 읽히지 않게 |
| env.lightness | 동일 | HSL L **≤ 0.30** | 코드 글자가 항상 더 밝게 |
| env.hueClash | 동일, chroma > 0.10일 때만 | 예약 hue 5개와 hueDistance **≥ 20°** | 하늘이 코드 색과 섞여 보이지 않게 |
| code.chroma | keyword·type·function·string·number | chroma **≥ 0.35** | |
| code.lightness | 동일 | L **≥ 0.62** | |
| code.contrast | 동일 vs cardBackground | **≥ 4.5 : 1** (WCAG AA) | |
| code.skyContrast | plain vs skyHorizon | **≥ 7 : 1** (WCAG AAA) | 카드 밖에 뜬 글자도 읽히게 |

보정 여유: 생성기(`safeEnvironmentHue`)는 22°로 밀고 검증은 20°로 본다(2° 마진) — 그래서 Ocean/Nebula의 실효 hue가 입력과 다르다(§2.3). `floorGrid`는 2026-10-19부터 검증 대상에 포함되며 Tinted 채도를 0.30 → 0.26으로 낮춰 chroma 0.146으로 통과한다(Tech PRD O4 해결).

---

## 3. 타이포그래피

| 용도 | 서체 | 크기 / 규칙 |
|---|---|---|
| 코드(카드 텍스처·인스펙터) | **SF Mono**(없으면 Menlo) | 카드: 아틀라스 셀 64 px, 글리프 쿼드 높이 = 카드 반지름 × 0.055 (0.08 m 카드 → 4.4 mm, 0.32 m → 17.6 mm); 인스펙터: `.body.monospaced()` Dynamic Type |
| UI(Dashboard·HUD·인스펙터 라벨) | **SF Pro** 텍스트 스타일 | `.title2` 섹션, `.body` 본문, `.caption` 메타. 고정 pt 금지 |
| 이름판(아바타) | SF Pro Rounded Semibold | 텍스처 512×128 px, 이름 ≤ 14자 말줄임 |
| 말풍선(AI) | SF Pro | 공간: 폭 0.42 m, 텍스처 1024×512; 2D: `.callout` |
| 다이어그램(SVG) | SF Pro Text, Helvetica, Arial fallback | ≥ 14 px |

카드 텍스처 크기: 반지름 0.08–0.16 m → 512×512, 0.16–0.24 → 1024×1024, 0.24–0.32 → 1536×1536. `TextureFactory`가 비동기 생성하며, 코드 텍스트가 그려진 **전용 텍스처는 400장**까지(가중치 상위), 나머지 카드는 레이어 색 솔리드. 씬에 올리는 노드는 2500개까지(`ConstellationSceneController.maxNodeEntities`).

---

## 4. 공간 레이아웃 치수

| 요소 | 치수 | 출처 |
|---|---|---|
| 사용자 원점 | (0, 0, 0), 앞 = −Z | visionOS 이머시브 |
| 루트 노드 | 원점 위 **1.5 m** (`rootHeight`) | `LayoutConfiguration` |
| 셸 1 반지름 | **1.6 m** (`baseRadius`) | |
| 셸 간격 | **1.25 m** (`shellSpacing`) → 셸 2…5 = 2.85 / 4.1 / 5.35 / 6.6 m | |
| 섹터 간격 | 0.04 rad (≈ 2.3°) | |
| 카드 반지름 | **0.08 – 0.32 m** — `0.08 + √lines / 90` (100줄 0.19 m, 400줄 0.30 m, 467줄+ 포화) | `RadialShellLayout.cardRadius` |
| 수직 지터 | ± 0.35 m | |
| 호스트 오브 | 반지름 **0.12 m**, 사용자 앞 **0.9 m**, 눈높이 −0.1 m | VISION |
| 클러스터 오브 | 반지름 **0.18 m**, 멤버 centroid | |
| 스테이지 링 | 반지름 **1.2 m**, 참가자 자리 6(60° 간격), 사용자 뒤쪽 반원 우선 | |
| 아바타 흉상 | 높이 **0.45 m**, 바닥 기준 | |
| 비콘 | 높이 **3 m**, 링 2개(반지름 0.25 / 0.45 m, 높이 0.02 / 1.0 m) | |
| 리뷰 핀 | **0.08 m**, 카드 윗변에 바늘 끝을 꽂고 역할 별 오른쪽부터 한 줄(최대 6개, 좁은 카드에서는 35 %까지 축소) | `CodeNodeEntity.layoutPins` |
| 포인터 다트 | **0.05 m** | |
| 소환 복제 카드 | 사용자 앞 **0.7 m**, 높이 1.1 m(손 높이) | FR-5.4 |
| 타임 다이얼 변위 | `timeDepth` 1.2 m × t × dial (반경 방향) + 그 35 % (높이) | FR-2.7 |

**레이어 밴드 높이**

| 레이어 | y (m) | 색 | 아이콘(이중 부호화) |
|---|---|---|---|
| presentation | 2.10 | cyan `#5EE1FF` | `rectangle.on.rectangle` |
| domain | 1.60 | lavender `#C9B6FF` | `cube` |
| unknown | 1.30 | `#A7ADBF` | `questionmark` |
| data | 1.15 | amber `#FFD166` | `cylinder` |
| infrastructure | 0.75 | grey `#8A93A6` | `wrench` |
| test | 0.50 | lime `#B8FF7A` | `checkmark.seal` |

### 4.1 레이아웃 스타일 (`LayoutStyle`, 기본 `.celestial`)

그래프의 형태는 CoulsonPortfolioWeb `Public/js/space/layouts/*`(sphere / treeRadial / grid / spiral)를 미터 단위로 포팅한 5종 + 새 기본값 천구(celestial)다. 어떤 스타일이든 색·크기·별 모양·시간(w)의 의미는 같고 **위치 규칙만** 바뀐다(Dashboard·메뉴에서 선택, SharePlay로 동기화, `UserDefaults` 영속).

| 스타일 | 축의 의미 (`LayoutStyle.axes`) | 치수 | 시간 투영 |
|---|---|---|---|
| **천구 · Celestial** (기본) | 거리 = 트리 깊이 · 방위 = 서브트리 섹터 · **고도 = 레이어**(presentation 34° / domain 18° / unknown 8° / data 0° / infrastructure −9° / test −15°, ±4.5° 지터) · 바깥 = 최근 | 눈높이 1.45 m 중심 구면 셸 1.6 + 1.25 m·(d−1), 루트 = 머리 위 "북극성"(1.45 + 1.76 m), 카드 중심 ≥ 바닥 0.35 m | 구면(중심에서 3D 방향으로 밀기) |
| 셸 · Shells | 반지름 = 깊이 · 각도 = 서브트리 · 높이 = 레이어 밴드(위 표) | v1 원반, 높이 0.35–2.4 m | 원통(수평 + 35 % 들림) |
| 구 · Sphere | 피보나치 돔에 경로 순서 · 폴더 = 바깥 허브 | 반지름 ≥ 2.4 m, 세로 0.66 | 구면 |
| 트리 방사형 · Tree radial | 링 = 깊이 · 각도 ∝ 서브트리 파일 수 · 높이 = 레이어 | 링이 잎 수에 맞춰 커짐 | 원통 |
| 벽 · Wall | 열·행 = 경로 순서(프리오더) · 폴더 = 블록 머리 | 사용자 앞 원통형 곡면 벽 | 원통 |
| 나선 · Spiral | 높이·회전 = 경로 순서 | 상승 나선 | 원통 |

천구에서는 레이어 사이의 세로 간격이 깊이와 함께 커져(같은 각도라도 멀수록 높이 차가 큼) v1 원반의 "2 m 두께" 한계가 사라진다. 셸 반지름(1.6 + 1.25 m·k)은 바닥 아스트롤라베의 링과 같다 — 원반(Shells)에서는 카드가 링 바로 위에 서고, 천구에서는 같은 반지름이 눈높이 중심의 구면 거리가 된다(§9 `Floor_Grid`).

### 4.2 별(노드 글리프) 배치 — `StarEncoder`

| 채널 | 의미 | 값 |
|---|---|---|
| 모양 | 역할 `CodeRole`(App · View · Controller · ViewModel · Model · Service · Extension · Test · Doc · Config · Script · Other) + 허브(Folder · Module) | `NodeStars.usdz` 프림 14종 |
| 색 | 아키텍처 레이어(카드 띠와 같은 색) | `theme.color(for: layer)` |
| 크기 | 결합도 — 이 파일에 의존하는 파일 수(Ca) | `min(0.11, 0.045 + 0.012·log2(1 + Ca))` m, 폴더 0.075, 모듈 0.12 |
| 발광 | 최근성 w | glow = 0.45 + 0.55 w → emissive 0.5 + 0.5 × round(4 · glow) |
| 헤일로 | 선택한 노드의 파일이 속한 **의존 순환**의 모든 파일 | `Star_Halo`, `#FF5F6D` |

위치: 카드 로컬 좌표 `(−w/2 + 0.55 s, h/2 + 0.65 s, +0.01)` — 좌상단 모서리 바로 위(제목을 가리지 않음, `StarEncoder.anchor`). 카드 폭과 무관하게 미터 크기 일정. 2500 카드 중 별은 최대 1200개(허브 → Ca 순)로 드로콜 예산을 지킨다.

---

## 5. 오브 디자인

### 5.1 레이어 구조 (CoulsonAndJarvis 계승)

```
HostOrb (반지름 0.12 m)
├─ Core        구 r=0.045, 머티리얼 Core: 거의 흰색(#F7F7FF) 발광, 에너지 × 2.5 emissive
├─ Halo        빌보드 쿼드 r=0.12, 머티리얼 Accent: theme.orbHalo, 가우시안 알파, 에너지 × 1.4
├─ Band ×4     토러스 r=0.07…0.11, 두께 0.004, 머티리얼 Band0…Band3(밴드마다 별도 슬롯 — USD에서 각자 emissive 색 유지): theme.orbBands[i], 서로 다른 축·속도로 회전
├─ Particle aura  ParticleEmitter r=0.14, 방출률 = 40 × 에너지, 수명 1.2 s, 색 = Halo
├─ Shell       유리 구 r=0.12, 머티리얼 Glass: 투명 0.85, 굴절 1.1, 프레넬 림 = Halo 20 %
└─ PointLight  강도 = 120 lm × 에너지, 색 = Halo
```

클러스터 오브(0.18 m)는 Shell + 내부 격자(머티리얼 `Shell`, 레이어 색 틴트) + 중앙 희미한 Core만 갖는다. 도킹되면 격자가 `orbHalo`로 물들고 호스트의 Band ×4가 셸 안에서 회전한다.

### 5.2 상태별 에너지

| 상태 | 에너지 | Core 발광 | 밴드 회전 | 파티클/s | 펄스 | 사운드 |
|---|---|---|---|---|---|---|
| idle | **0.22** | 은은 | 0.15 rad/s | 9 | 호흡 4 s, 진폭 3 % | — |
| listening | **0.55** | 중간 | 0.6 rad/s | 22 | 1.2 s, 6 % | 상승음 |
| thinking | **1.00** | 최대 | 2.4 rad/s, 축 흔들림 | 40 | 0.5 s, 8 % | 저음 루프 |
| speaking | **0.75** | 높음 | 1.0 rad/s | 30 | 음성 진폭 추종 | TTS |
| unavailable(AI 불가) | 0.22 | 회색 코어 | 0.1 | 0 | — | — |

에너지 전환은 0.35 s 이징(easeInOut). 상태 → 에너지는 Free/Docked 동일.

### 5.3 Dock / Undock 모션 (0.6 s)

| 단계 | 시간 | 내용 |
|---|---|---|
| Dock 0→0.25 | 0.15 s | 호스트 오브 스케일 1.0→0.8, 파티클 방출 2× |
| Dock 0.25→0.9 | 0.39 s | 3차 베지어로 클러스터 오브 중심까지 비행(제어점: 출발 위 0.3 m, 도착 앞 0.2 m), 스케일 →0.35 |
| Dock 0.9→1.0 | 0.06 s | 클러스터 셸 틴트 → orbHalo 크로스페이드, 짧은 플래시 |
| Undock | 역재생 0.6 s | 드래그 임계 0.25 m 통과 순간 시작, 손 위치로 복귀 후 Free 위치로 0.8 s 보간 |

Reduce Motion: 비행 대신 크로스페이드 0.4 s.

---

## 6. 아바타 디자인 ("나의 모습")

| 항목 | 규격 |
|---|---|
| 모델 | `Avatar_Bust.usdz`, 스타일라이즈드 흉상(머리·목·어깨 단순 형태), 높이 0.45 m, 바닥 피벗 |
| 머티리얼 | `Shell`(흉상 본체: 환경 규칙 — L 0.22, chroma 0.08, 테마 fog 쪽), `Accent`(어깨 라인·이름판 링: 참가자 액센트 색, 발광 0.6) |
| 액센트 색 | `HSL(hue(theme.avatarAccent) + participant.hueOffset, 0.6, 0.68)`; hueOffset은 입장 순서 × 47°(황금각 근사)로 6명이 서로 다르게 |
| 이름판 | 흉상 위 0.08 m, 빌보드 0.22 × 0.055 m, SF Pro Rounded Semibold, 배경 카드배경색 78 %, 테두리 액센트 |
| 방장 표식 | 이름판 왼쪽 작은 오브 아이콘(orbHalo 색) |
| 상태 | 말하는 중(마이크 레벨) → 이름판 테두리 펄스; 포인터 사용 중 → 어깨 Accent 밝기 1.3× |
| Persona 공존 | visionOS 참가자 Persona가 있으면 흉상은 숨기고 이름판만 Persona 위에 |

---

## 7. 이펙트

| 이펙트 | 구성 | 색 | 타이밍 |
|---|---|---|---|
| **비콘** | `Beacon.usdz`(코어 빔 + 반투명 외피 + 트랙터 링 3 + 바닥 메달리온); 없으면 `FX_Beam` 교차 쿼드 2장. 바닥 물결 2개 = `FX_Ring` 스프라이트(0.3 → 2.4 m, 반 주기 엇갈림, 페이드) | `theme.beacon` `#FFD166` | 등장 0.5 s(바닥에서 솟음), 유지 → 해제 0.3 s |
| **소환 가이드선** | 원본 카드 ↔ 복제 카드 실선(두께 0.003 m), 점 흐름 | `highlight` 60 % | 복제 카드 비행 0.9 s 동안 그려지고 유지 |
| **선택·하이라이트 글로우** | 카드 뒤 `FX_CardGlow` 쿼드(카드 + 사방 0.08) — 카드 외곽 SDF의 선명한 림 + 부드러운 외광. 없으면 단색 프레임 | 선택 = `code.plain`, AI 하이라이트 = `highlight` | 즉시 |
| **레이저 포인터** | 참가자 위치 → 목표점 얇은 선(0.002 m) + `Pointer_Dart.usdz` | 참가자 액센트 | 10 Hz 갱신, 0.5 s 미수신 시 페이드 |
| **리뷰 핀** | `ReviewPin.usdz` 0.08 m, 미해결 = 액센트 발광, 해결 = 회색 | 작성자 액센트 | 꽂힐 때 0.25 s 바운스 |
| **관계 튜브** | 관계 종류별 2차 베지어 튜브(§7.3), `FX_EdgeRamp`로 출발 0.28 → 도착 1.0 밝기(정지 화면에서도 방향이 읽힘), 타입 계열은 점선(0.06 / 0.045 m), flow 계열과 포커스 엣지는 화살촉(t ≈ 0.96) | `RelationKind.style.color`(테마 불변), 트리선 `edgeContains` | 즉시 재구성(백그라운드 빌드) |
| **흐름 파티클** | flow 계열 엣지를 따라 흐르는 스프라이트 — 보통 `FX_Glow` 4.5 cm, 포커스 `FX_Spark`(회절 스파이크) 7.5 cm, 경로 양 끝 12 %에서 커지고 작아짐 | 관계 색 + 밝게 | 0.42 m/s(포커스 0.55), 최대 240개, Reduce Motion 25 % |
| **포커스 디밍** | 선택이 있고 관계 모드 ≠ off이면 선택과 관계로 이어진 카드만 남고 나머지는 불투명도 0.22 | — | 엣지 재구성과 함께 |
| **순환 헤일로** | 선택 노드의 파일이 의존 순환에 있으면 순환의 모든 파일 별에 `Star_Halo`, 순환 엣지는 붉은 굵은 튜브 | `#FF5F6D` | 선택 시 |
| **타임 다이얼 잔상** | 다이얼 조작 중 카드 이동 궤적 얇은 선 | 레이어 색 30 % | 조작 종료 후 0.4 s 페이드 |

---

## 7.1 카드 상태

| 상태 | 테두리(`cardBorder`) | 배경 | 추가 요소 | 전환 |
|---|---|---|---|---|
| 기본 | 흰 14 % | `#0E1220` 78 % | 레이어 밴드 색 왼쪽 띠, 헤더 오른쪽 **역할 칩**(역할 색), 부제 `kind · layer · lines · in Ca / out Ce`, 좌상단 위 **별** | — |
| 호버/시선 | 흰 30 % | 동일 | 살짝 확대 1.04× | 0.15 s |
| 선택 | `FX_CardGlow` (plain) | 82 % | 인스펙터 동기화, 관계 포커스(강조 튜브 + 스파크 파티클), 나머지 디밍 | 0.2 s |
| AI 하이라이트 | `FX_CardGlow` (`highlight`) | 동일 | 디밍 제외 | 0.3 s |
| 디밍(포커스 밖) | 동일 | 동일 | 엔티티 전체 불투명도 0.22 (`OpacityComponent`). 선택 노드의 내용물·하이라이트된 카드는 디밍 안 함 | 엣지 재구성 · 하이라이트 변경 시 |
| 소환 복제 | `highlight` 60 % | 90 % (더 불투명) | 원본과 가이드선, 닫기 버튼 | 0.9 s 비행 |
| 핀 있음 | 기본 | 기본 | 윗변 `ReviewPin`(별 오른쪽, 미해결 개수만큼, 테마 비콘 색) | 0.25 s 바운스 |
| LOD(멀리) | 없음 | 레이어 색 40 % 솔리드 | 텍스트 없음 | 거리 > 6 m에서 크로스페이드 |
| 읽기 불가/구조만 | 회색 점선 | 60 % | "구조만 보기" 아이콘 | — |

## 7.2 사운드

| 이벤트 | 소리 | 길이 |
|---|---|---|
| 웨이크워드 감지 | 상승 2음(짧은 글라스) | 0.25 s |
| 응답 시작 | 부드러운 톤 1음 | 0.15 s |
| dock | 흡입음 + 저음 탁 | 0.6 s |
| undock | 역재생 | 0.6 s |
| 비콘 등장 | 공간감 있는 벨 | 0.8 s |
| 핀 꽂기 | 짧은 클릭 | 0.1 s |
| 투어 스텝 전환 | 2음 차임 | 0.3 s |

모든 소리는 공간 오디오(`SpatialAudioComponent`)로 해당 엔티티 위치에서 재생하고, 설정에서 끌 수 있다. 음량은 −18 LUFS 기준 통일.

## 7.3 관계 시각 언어 (`RelationKind`, 포트폴리오 `EDGE_TYPES` 포팅)

구조 엣지(`EdgeKind`: imports / inherits / references / calls)는 그대로 두고, 그 위에 **무엇을 하는 관계인지**(`RelationKind`)를 `RelationClassifier`가 붙인다. 색은 코드 팔레트처럼 테마와 무관하게 고정이라 범례의 의미가 바뀌지 않는다. 방향은 항상 "의존하는 쪽 → 의존받는 쪽"이고, 데이터가 거꾸로 흐르는 `binds`만 화살표·파티클을 뒤집어 그린다.

| 관계 | 색 | 선 | flow(화살촉·파티클) | lane(rad) / altitude | 뜻 |
|---|---|---|---|---|---|
| 화면 전환 · Presents | `#FF9E64` | 실선 | ● | 1.22 / 1.45 | sheet / NavigationLink / WindowGroup / present → 목적지 |
| 상태 흐름 · Binds | `#9ECE6A` | 실선 | ●(역방향) | 0.87 / 1.15 | @State / @Environment / @Bindable … 데이터 원본 → 뷰 |
| 알림 · Notifies | `#FFD60A` | 실선 | ● | −1.31 / 1.6 | 같은 Notification 이름 post → observe |
| 생성 · Creates | `#E0AF68` | 실선 | ● | −0.96 / 1.25 | 생성하는 곳 → 생성되는 타입 |
| 뷰 포함 · Composes | `#7AA2F7` | 실선 | — | 0.44 / 1.0 | 부모 뷰 → 자식 뷰 |
| 델리게이트 · Delegates | `#F7768E` | 점선 | ● | −0.35 / 1.05 | 구현 → 델리게이트 프로토콜 |
| 채택·상속 · Conforms | `#BB9AF7` | 점선 | — | −0.62 / 0.85 | 타입 → 프로토콜/부모 |
| 호출 · Calls | `#FFD166` | 실선 | ● | −1.1 / 1.3 | 함수 → 함수(예약) |
| 확장 · Extends | `#7DCFFF` | 점선 | — | 0.18 / 0.7 | extension → 원본 타입 |
| import · Imports | `#58D7E8` | 실선(조용) | — | 0 / 0.38 | 파일 → 모듈/최상위 폴더 |
| 타입 참조 · Uses | `#8B93A5` | 실선(조용) | — | 0 / 0.55 | 사용 → 정의 (가장 흔하고 정보가 적어 가장 흐리게) |

- **곡선**: 포트폴리오 그대로 2차 베지어, 불룩함 `min(1.4, 0.25·dist + 0.16) m × altitude`, 구조 중심에서 바깥으로(이머시브에서는 사용자를 향해 안쪽으로). **lane**은 불룩한 방향을 현(chord) 축으로 회전시켜, 같은 두 카드 사이의 서로 다른 관계가 겹치지 않고 3D 공간에서 갈라진다 — "고차원 구분".
- **굵기**: uses/imports 2.1 mm, 그 외 3.1 mm, × (faint 0.8 / normal 1 / focus 1.6) × (1 + 0.25·log2 weight), 순환 ×1.4.
- **불투명도**: 트리선 0.30(포커스 밖 0.10), uses·imports 0.26, 나머지 0.62, 포커스 0.95, 순환 0.85.
- **모드**(포트폴리오 `L` 키): off(트리선만) → focus(선택과 닿는 관계만) → all. ⌘L / 메뉴 / 툴바 / 인스펙터에서 순환, 범례에서 종류별 숨김.
- **예산**: 관계 1500개(포커스 → 우선순위 → weight 순), 포커스 밖 엣지가 600개를 넘으면 uses부터 제외, 파티클 240개.

**역할 추론**(`CodeRole`, 포트폴리오 `inferRole`): 경로·파일명·심볼·소스로 App / View / Controller / ViewModel / Model / Service / Extension / Test / Doc / Config / Script / Other를 정한다. 카드의 역할 칩과 별의 모양, `composes`(뷰→뷰) / `creates`(그 외) 구분에 쓰인다.

## 8. 테마별 무드보드

| 보드 | 이미지 | 설명 |
|---|---|---|
| Dark 전체 씬 | `../Blender/renders/theme_dark.png` | 기본 테마. 월드 = `Sky_Dark.png`, 바닥 그리드 emissive `#2A3150`, 라벤더 헤일로 호스트 오브 |
| Tinted Ocean | `../Blender/renders/theme_tinted_ocean.png` | 월드 = `Sky_Tint.png` × `HSL(210, 0.34, 0.17)`, 액센트 `HSL(210, 0.75, 0.72)` (앱의 실효 hue는 213.2°) |
| 에셋 시트 | `../Blender/renders/asset_sheet.png` | 7 에셋을 동일 조명·스케일로 나열 |
| HostOrb | `../Blender/renders/host_orb.png` | 코어·밴드 4(Band0…Band3)·셸 |
| ClusterOrb | `../Blender/renders/cluster_orb.png` | 얇은 유리 + 내부 격자 |
| Avatar_Bust | `../Blender/renders/avatar_bust.png` | 흉상 + 이름판 링 |
| Beacon | `../Blender/renders/beacon.png` | 빛기둥 + 2중 링 |
| ReviewPin | `../Blender/renders/review_pin.png` | |
| Stage_Ring | `../Blender/renders/stage_ring.png` | 6자리 |
| Pointer_Dart | `../Blender/renders/pointer_dart.png` | |

렌더 공통: Cycles(Metal) 64 샘플 · OIDN 디노이즈 · **AgX** 뷰 트랜스폼(강도 4 emissive가 부드럽게 롤오프) · 컴포지터 Bloom 글레어 · 1280×960. 앱 아이콘(`AppIcon-1024.png`, `Docs/images/icon-256.png`)도 같은 씬에서 렌더.

무드 키워드: Dark = "천문대 밤", Ocean = "심해 관측실", Moss = "이끼 낀 서고", Ember = "꺼져가는 화로", Nebula = "성운 전망대". 어떤 테마든 코드 색은 변하지 않는다는 것이 무드보드의 핵심 메시지다.

---

## 9. 에셋 명세

| 파일 | 용도 | 치수 | 머티리얼 슬롯 | 폴리 예산(삼각형) | 폴백(에셋 없을 때) |
|---|---|---|---|---|---|
| `HostOrb.usdz` | 호스트 AI 오브 — v2 **혼천의**: 코어 r 0.054, 적도·자오선 2·황도(23.4°) 링(Band0…3), 72눈금 다이얼, 내부 9별 별자리, 유리 셸 r 0.135 | r 0.135 m | `Core`, `Band0`·`Band1`·`Band2`·`Band3`, `Glass` | 9 788 (≤ 14k) | 코드 생성 구 + 토러스 4 |
| `ClusterOrb.usdz` | 클러스터 오브 — 측지 격자(베벨 스트럿 + 관절 별), 기울어진 궤도 링 2, 작은 코어 | r 0.18 m | `Shell`, `Glass`, `Core` | 3 816 (≤ 6.5k) | 와이어 구 |
| `Avatar_Bust.usdz` | 참가자 — 테이퍼 어깨 + 액센트 파이핑, 바이저 헬멧, 헤드셋·마이크 붐, 칼라 링, 이름판 링 | h 0.45 m | `Base`, `Accent` | 7 042 (≤ 9.5k) | 캡슐 + 링 |
| `Beacon.usdz` | 소환 비콘 — 코어 빔 + 반투명 외피, 트랙터 링 3, 상단 보석, 바닥 메달리온(48눈금) | h 3 m | `Accent`, `Core`, `Glass`, `Base` | 3 500 (≤ 6k) | `FX_Beam` 교차 쿼드 → 실린더 |
| `ReviewPin.usdz` | 리뷰 핀 — 강철 바늘, 액센트 칼라, 라운드 브릴리언트 보석 머리 | 0.08 m | `Accent`, `Base` | 488 (≤ 1.2k) | 콘 + 구 |
| `Stage_Ring.usdz` | 회의 스테이지 — 아스트롤라베 띠 + 발광 인레이, 72 각도 눈금, 육각 좌석 패드 6, 유리 중심 나침반 장미 | r 1.2 m | `Shell`, `Accent`, `Glass` | 6 712 (≤ 9k) | 토러스 + 디스크 6 |
| `Pointer_Dart.usdz` | 레이저 포인터 끝 — 육각 쌍뿔 크리스털 + 허리 칼라 | 0.05 m | `Accent` | 156 (≤ 300) | 콘 |
| `NodeStars.usdz` | 노드 별 글리프 15 프림(§4.2 표 + `Star_Halo`), 한 줄 배치(x = i · 0.16 m), 최대 치수 0.1 m, 플랫 셰이딩 | 0.1 m | `Accent`, `Glass`(헤일로) — 앱이 레이어 색 PBR로 교체 | 글리프당 ≤ 220 (합 1 169) | 작은 발광 구 |
| `Textures/FX_Glow.png` | 가우시안 코어 + 지수 꼬리 글로우(흰 RGB + 알파) | 256² | — | — | `TextureFactory.glowDot` |
| `Textures/FX_Spark.png` | 점 코어 + 회절 스파이크 4 + 대각 4 | 256² | — | — | glowDot |
| `Textures/FX_Ring.png` | 물결 링(r 0.4) + 안쪽 가는 선 + 옅은 채움 | 512² | — | — | 압출 링 |
| `Textures/FX_Beam.png` | 빛기둥 단면(코어 + 외피, 바닥 플레어, 위로 페이드) | 64×512 | — | — | 실린더 |
| `Textures/FX_EdgeRamp.png` | 엣지 진행 방향 밝기 램프(u 0 → 1) | 256×8 | — | — | 단색 튜브 |
| `Textures/FX_CardGlow.png` | 카드 외곽 SDF 림 + 외광(카드 + 사방 0.08) | 580×424 | — | — | 단색 프레임 |
| `Textures/Sky_Dark.png` | Dark 하늘 등장방형 — Cycles 파노라마, 순수 emission `Field` 그래프: 부드러운 수평선 헤이즈, **은하수**(사용자 정면 18° 위 벌지, 58° 기울기, 별 구름 + 먼지 균열), 성운 2층(인디고·자두), **별 등급 4단계**(띠 안 미분해 입자 / 약 / 중 / 밝음 + 헤일로, 거듭제곱 밝기, 색온도 틴트) | 4096×2048 | — | 12 샘플, **디노이즈 OFF** — 블록 중앙값 OKLab L ≤ 0.29, chroma ≤ 0.06 | numpy 폴백(`--fallback`, v1 룩) |
| `Textures/Sky_Tint.png` | Sky_Dark의 8-bit 그레이스케일 밝기 맵(8×8 블록 평균으로 정규화, 최댓값 1.0); 앱이 테마 hue를 곱함 | 4096×2048 | — | — | 동일 |
| `Textures/Floor_Grid.png` | **아스트롤라베 바닥**(24 m) — 깊이 셸 반지름(1.6 + 1.25k m) 링 + 5°/15° 눈금, 반 셸 원, 15° 스포크 24(방위 4개 강조), 중심 1 m 격자, 원점 레티클, 11 m 베젤, 방사형 페이드. 흰 RGB straight-alpha | 2048×2048 | — | — | 코드 생성 그리드 |

공통 규칙: 단위 미터, +Y up, 앞 −Z(Blender +Y → USD −Z; 아바타 얼굴·다트 끝이 이 방향), 피벗 = 바닥 중심(오브는 중심). 에셋 자체 색은 환경 규칙(chroma ≤ 0.16, L ≤ 0.30)을 따르고, 발광은 `Accent` 슬롯과 오브 `Core`/`Band*`만(Core = `#E9E4FF` × 4). 머티리얼 이름은 고정 — `Core`, `Band0…Band3`, `Shell`, `Accent`, `Glass`, `Base` — 앱(`AssetLoader`)이 이름으로 찾아 `PhysicallyBasedMaterial`로 **교체**하므로 USDZ의 PBR 값은 "미리보기용"이다. 모든 USDZ는 zip 무결성·`upAxis`·머티리얼·bbox·삼각형(< 20k)·크기(< 2 MB) 검사와 `usdchecker --arkit`를 통과했다.

**v2 렌더**: `Blender/renders/layout_gallery.png`(6 스타일), `layout_celestial_eye.png`(사용자 시점), `node_stars.png`(글리프 범례), `relation_legend.png`(관계 범례) — 모두 Kit이 계산한 실제 배치(`Blender/data/*.json`)로 렌더.

---

## 10. Blender 파이프라인

`.blend` 파일은 두지 않는다 — 스크립트가 단일 소스다(상세: `Blender/scripts/README.md`). Blender 5.2.2, `/Applications/Blender.app`.

- **실행** (헤드리스 CLI, `Blender/scripts/`에서):

```sh
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER --background --python build_all.py          # 에셋 → 별·FX → 텍스처 → 렌더 → 별자리 렌더 → 아이콘
./make_icon_set.sh                                   # 아이콘 세트 다운스케일 + Docs/images/icon-256.png
$BLENDER --background --python build_assets.py -- HostOrb Beacon     # USDZ 부분 재생성
$BLENDER --background --python build_graph_assets.py                 # NodeStars.usdz + FX_*.png
$BLENDER --background --python render_graph.py                       # 레이아웃 갤러리 + 범례 (Blender/data/*.json)
$BLENDER --background --python build_textures.py -- --fallback       # numpy 하늘(수 초)
$BLENDER --background --python build_textures.py -- --derived-only   # 기존 Sky_Dark에서 Sky_Tint·Floor_Grid만
$BLENDER --background --python render_assets.py -- host_orb theme_dark
```

`build_all.py` 플래그: `--skip-assets --skip-graph --skip-textures --skip-renders --skip-graph-renders --skip-icons --fallback-sky`. 별자리 렌더의 입력 JSON은 `cd ConstellateKit && CONSTELLATE_SNAPSHOT_DIR=../Blender/data swift test --filter SnapshotTests`로 다시 만든다.

- **스크립트 목록**:

| 스크립트 | 역할 / 산출물 |
|---|---|
| `constellate_lib.py` | 공용 헬퍼 — 팔레트, 머티리얼(`Core`, `Band0…Band3`, `Shell`, `Accent`, `Glass`, `Base`), 프리미티브, USDZ 내보내기+검증, PNG 작성(zlib), Cycles/Metal 설정, 글레어, 카메라 프레이밍 |
| `build_assets.py` | `Resources/Assets3D/{HostOrb,ClusterOrb,Avatar_Bust,Beacon,ReviewPin,Stage_Ring,Pointer_Dart}.usdz` |
| `build_graph_assets.py` | `Resources/Assets3D/NodeStars.usdz` + `Resources/Textures/FX_{Glow,Spark,Ring,Beam,EdgeRamp,CardGlow}.png` (`--stars-only`, `--fx-only`) |
| `build_textures.py` | `Resources/Textures/{Sky_Dark,Sky_Tint,Floor_Grid}.png` (`--fallback`, `--derived-only`, `--sky-only`, `--floor-only`) |
| `render_graph.py` | `Blender/renders/{layout_<style>,layout_celestial_eye,layout_gallery,node_stars,relation_legend}.png` + README 히어로 `Docs/images/hero.png` (`--quick`, `--eye`, `--gallery`, `--stars`, `--legend`, `--hero`) |
| `render_assets.py` | `Blender/renders/{host_orb,cluster_orb,avatar_bust,beacon,review_pin,stage_ring,pointer_dart,theme_dark,theme_tinted_ocean,asset_sheet}.png` + `AppIcon-1024.png` (`--icon-only`) |
| `build_all.py` | 위 전부 순서 실행 (`--skip-*`, `--fallback-sky`) |
| `make_icon_set.sh` | `icon_16 … icon_1024.png`(appiconset) + `Docs/images/icon-256.png` (sips) |
| `README.md` | 파이프라인 문서 |

- **내보내기 설정**: Blender Z-up 미터로 제작 → `convert_orientation`(up **Y**, forward **−Z**; 루트 `Xform`에 `rotateXYZ(−90,0,0)`), 스테이지 메타 `upAxis = Y`, `metersPerUnit = 1`. `triangulate_meshes=True`, `export_materials=True`, `generate_preview_surface=True` → `UsdPreviewSurface`, emission 강도는 `emissiveColor`에 베이크. **Blender 5.2는 Principled Alpha 소켓을 무시**(transmission → opacity만 매핑)하므로 `export_usdz()`가 번들 `pxr`로 패키지를 다시 열어 반투명 머티리얼에 `inputs:opacity`를 쓰고 `UsdUtils.CreateNewUsdzPackage`로 재패키징한다. Transmission은 렌더 전용. 매 USDZ 검증: zip 무결성·`upAxis`·머티리얼·bbox·삼각형 < 20k·크기 < 2 MB, `usdchecker --arkit` 통과.
- **텍스처**: `Sky_Dark` Cycles 12 샘플(가우시안 별 프로파일이라 AA 샘플이 적어도 됨), 픽셀 필터 1.0, 디노이즈 OFF(emission-only 월드라 MC 노이즈가 없고 OIDN이 별을 뭉갬). `Sky_Tint` 8×8 블록 평균 정규화 그레이스케일. `Floor_Grid` straight-alpha, 거리 기반 해석적 안티앨리어싱, 컬러 매니지먼트 없음.
- **FX 스프라이트**: 방사 평면 + `Field` 수식(가우시안·지수 꼬리·둥근 사각형 SDF) → Cycles 직교 카메라 → 선형 EXR → `RGB = 255, A = 필드` PNG. 뷰 트랜스폼이 끼지 않아 수식 = 알파.
- **렌더**: Cycles on Metal 64 샘플, OIDN, AgX, 컴포지터 Bloom, 1280×960. 월드 = `Sky_Dark.png`(dark) / `Sky_Tint.png × HSL(210,0.34,0.17)`(ocean), 바닥 = 그리드 텍스처 emissive `#2A3150`.
- **MCP 노트**: 이번 세션(2026-10-19)에는 Blender MCP 서버가 연결되지 않아 전부 CLI로 생성했다. 스크립트는 `sys.argv` 없이도 상수 기본값으로 동작하므로 MCP가 연결되면 같은 본문을 `execute_blender_code`로 실행할 수 있고, 두 경로의 산출물은 동일해야 한다(교차 검증은 TASKS T7.6).
- 실패 시 앱은 §9 폴백 메시로 진행하므로 에셋은 빌드 차단 요소가 아니다.

---

## 11. 플랫폼별 UI 와이어

### 11.1 visionOS — 창 + 이머시브

```
┌─ Dashboard (창, 0.6 × 0.5 m) ─────────────────────────────┐
│ [프로젝트 열기 ▾]  OrbitNotes · 41 files · 6.2k lines      │
│ ─────────────────────────────────────────────────────────── │
│ 참가자  ● 지연(host)  ● 도윤  ● 하린          [SharePlay ▸] │
│ 테마   (Dark)(Ocean)(Moss)(Ember)(Nebula)  hue ───○──────  │
│ 뭉치   [folder | file | type | feature]                     │
│ 모드   [analysis | review | lecture]      follow-host [ ]   │
│ 타임 다이얼  −1 ────────○──────── +1                        │
│ 마이크 ● 듣는 중 "콘스텔…"            [별자리 열기/닫기]     │
└────────────────────────────────────────────────────────────┘
┌─ Inspector (보조 창) ──────────────┐   이머시브: 사용자 원점, 셸 1.6 m…,
│ Sources/App/NoteListView.swift     │   호스트 오브 앞 0.9 m, 말풍선 오브 위,
│ presentation · 182 lines · 3d ago  │   스테이지 링 뒤쪽, 비콘·핀·포인터
│ in: 2 references  out: 1 inherits  │
│ ┌ code (SF Mono, CodePalette) ───┐ │
│ │ struct NoteListView: View {    │ │
│ └────────────────────────────────┘ │
│ 핀 (2)  ○ 42: 강제 언래핑?  ● …    │
└────────────────────────────────────┘
```

### 11.2 iPadOS — 3열

```
┌ 네비게이터 ─┬─ 뷰포트 (RealityView + 궤도 카메라) ─────────┬─ 인스펙터 ─┐
│ ▾ OrbitNotes │                                              │ 경로·레이어 │
│   ▸ App      │        (별자리 · 오브 · 비콘)                 │ 관계 in/out │
│   ▸ Features │                                              │ 코드        │
│   ▸ Data     │                                              │ 핀          │
│ 클러스터 탭  │  ┌ HUD 캡슐 ───────────────────────────┐     │             │
│ 핀 탭        │  │ ◉ idle  🎙  dial ──○──  [file ▾]   │     │             │
└──────────────┴──┴─────────────────────────────────────┴─────┴─────────────┘
```

입력: 1손가락 드래그 회전, 핀치 줌, 2손가락 팬, 2손가락 길게 = 포인터, 펜슬 호버 = 하이라이트.

### 11.3 macOS — 3열 + 메뉴

iPad와 동일 3열. 메뉴바: **File**(Open Project… ⌘O, Export Pins…), **View**(Theme ▸, Granularity ▸, Time Dial, Follow Host, Reset Camera ⌘0), **Meeting**(Start SharePlay, Mode ▸ ⌘1/2/3), **Help**. 궤도 카메라: 드래그 회전, 스크롤 줌, ⌥드래그 팬, 우클릭 드래그 = 포인터. 스페이스 = 마이크 푸시투토크. ⌘F 검색.

---

## 12. 접근성

| 항목 | 규칙 |
|---|---|
| VoiceOver | 노드 라벨 "파일 NoteListView.swift, presentation 레이어, 182줄, 3일 전 수정"; 오브 "호스트 AI, 대기 중"/"클러스터 App, 12개 파일"; 비콘 "찾은 코드 위치"; 핀 "리뷰 핀, 미해결, 도윤: …". 2D 컨트롤은 전부 라벨·값·힌트 |
| Dynamic Type | 2D UI 전부 텍스트 스타일 기반. 인스펙터 코드도 `.monospaced()` 스타일. 접근성 크기에서 3열 → 2열(인스펙터 시트) |
| 색약 | 레이어 밴드는 **색 + 아이콘**(§4 표) 이중 부호화; 엣지 종류는 색 + 대시 패턴(imports 실선, references 점선, inherits 긴 대시, calls 점-대시); 오브 상태는 색 + 모션 + 사운드 |
| 대비 | 테마 규칙으로 보장(코드/카드 4.5, plain/하늘 7). UI 텍스트는 시스템 색 사용 |
| 음성 비의존 | 모든 음성 인텐트는 텍스트 필드·버튼으로도 가능 |
| 포커스 | iPad/mac 키보드 포커스 순서 네비게이터 → 뷰포트 → 인스펙터, 뷰포트 안 방향키로 노드 이동 |

---

## 13. 모션 가이드

| 전환 | 기본 | Reduce Motion |
|---|---|---|
| 오브 펄스 | 진폭 3–8 % | 진폭 30 %로 축소(≈1–2.4 %), 호흡 주기 유지 |
| 파티클(오라·엣지·비콘) | 100 % | 방출률 25 % |
| dock/undock 비행 | 베지어 0.6 s | 크로스페이드 0.4 s |
| expand/collapse | 카드 비행 0.6 s | 페이드 0.3 s |
| 소환 복제 카드 | 비행 0.9 s | 목적지에서 페이드인 0.4 s |
| 타임 다이얼 | 즉시 연속(0.1 s 쓰로틀) | 동일(위치 변화는 사용자 조작 결과이므로 유지), 잔상 선 OFF |
| follow-host 카메라(iPad/mac) | 0.6 s 보간 | 1.0 s 보간 + 끄기 안내 |
| 테마 크로스페이드 | 0.8 s | 0.8 s(색 변화만, 모션 아님) |
| 이징 | easeInOut(cubic) 통일, 스프링 금지(공간에서 오버슈트는 멀미 유발) | 동일 |

모든 전환은 사용자 머리를 움직이지 않는다(visionOS에서 카메라 이동 없음). 사용자 입력 없이 시작되는 모션은 오브 펄스·엣지 파티클뿐이다.
