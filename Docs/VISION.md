# Constellate — Vision & Shared Spec (v0.1, 2026-10-18)

> 한 줄: **팀이 이머시브 공간에 들어가, 프로젝트 전체 코드가 4차원 규칙으로 뿌려진 "코드 별자리"를 함께 걸으며 분석·리뷰·교육 회의를 하는 앱.** 방장(host)의 온디바이스 AI가 Siri 같은 오브(orb)로 떠 있고, 코드 뭉치(cluster)에 들어가 답하거나 떼어져 나와 따라다닌다.

앱/프로젝트/레포 이름: **Constellate** · Bundle ID `com.coulson.Constellate` · 플랫폼 **visionOS 27 / iPadOS 27 / macOS 27** (단일 멀티플랫폼 타깃 + `ConstellateKit` 로컬 패키지) · Swift 6 언어 모드 아님(Swift 5 모드 + 기본 MainActor 격리 + Approachable Concurrency) · Combine 금지, async/await.

## 출처 프로젝트에서 가져오는 것

| 출처 | 가져오는 것 | 버리는 것 |
|---|---|---|
| Immersive Code Calligram IDE | 글리프 아틀라스·수천 쿼드 단일 메시(알파 마스크), 이리데슨트 ShaderGraph(USDA inline), 프로시저럴 스카이돔/바닥 그리드, 디바운스 비동기 실행 패턴, 카드 텍스트를 "글자 흐름"으로 보여주는 캘리그램 연출 | DSL/인터프리터 (코드를 쓰는 게 아니라 읽는 앱) |
| CoulsonAndJarvis | Siri형 오브 엔티티(코어·헤일로·밴드 4·파티클 오라·글래스 셸·포인트라이트, Presence 에너지 상태기계), FoundationModels 세션 래퍼(가용성·prewarm·컨텍스트 초과 복구·휴리스틱 폴백), SpeechAnalyzer 파이프라인 + 웨이크워드, 머리 앞 소환(summon), 진행형 몰입(progressive) 전환 | 날씨/무드 생성 |
| CodeFlow3D | FlowGraph/AnchorPoint/Edge 모델 발상, 틸트 게이트 투영(Z를 연속 함수로), 단일 Canvas 엣지 렌더(파티클·글로우), 라인 정확 앵커, 레이어 밴드 색, 리뷰 핀 아이디어 | 손으로 박은 좌표, 3평면 Primitive |

## 핵심 개념

1. **Constellation(별자리)** — `CodeGraph`(트리: module→folder→file→type→member, 그래프: imports/references/inherits/calls)를 `ConstellationLayoutEngine`이 4D로 배치한다.
   - x,z: 계층 방사형 셸(root 원점, depth→반지름, 형제→각도 섹터를 서브트리 가중치로 분할 → 트리 구조가 공간에서 유지됨)
   - y: 아키텍처 레이어 밴드(presentation 위 ~ infrastructure 아래) + 결정적 지터
   - **w: 시간(최근 수정도 0…1)**. "타임 다이얼"(-1…1)로 w를 반지름·높이 변위로 투영. 연속 함수라 스냅 없음. 다이얼 0이면 순수 공간 배치.
   - 엣지는 트리 엣지(은은한 선) + 관계 엣지(종류별 색, 파티클 흐름). 그래프 형태도 공간에서 보존.
   - **v2(2026-10-19 3차 라운드) — 고차원 별자리**: 형태는 `LayoutStyle` 6종(기본 **천구**: 눈높이 중심 구면 셸, 깊이 → 거리, 서브트리 → 방위, 레이어 → 고도각, 최근 → 바깥 / 셸 / 구 / 트리 방사형 / 벽 / 나선 — CoulsonPortfolioWeb `layouts/*` 포팅). 관계는 의미(`RelationKind` 11종: 화면 전환·상태 흐름·생성·뷰 포함·채택·확장·델리게이트·알림·import·참조·호출)로 그리고, 종류마다 고정 색·점선·흐름·**3D lane**(같은 두 카드 사이의 서로 다른 관계가 공간에서 갈라짐). 각 카드 위 **별**이 역할·레이어·결합도·최근성을, 헤일로가 의존 순환을 말한다. 한 장면이 위치 3축 + 시간 + 관계 종류 + 방향 + 역할 + 결합도 + 순환을 동시에 싣는다.
2. **Orb(오브) = 임의 단위 코드 뭉치** — `ClusterGranularity`(folder/file/type/feature)로 뭉친 `CodeCluster`마다 Siri형 오브가 중심(centroid)에 뜬다. 오브 안에는 멤버 코드 카드들이 접혀 있고, 가까이 가거나 탭하면 펼쳐진다(expand).
3. **Host AI(방장 AI)** — 방장 기기의 FoundationModels 온디바이스 모델. 자유 상태에선 독립 오브(흰 코어 + 테마 헤일로)로 사용자 앞 0.9m에 떠 있다.
   - **Dock(들어가기)**: 클러스터 오브를 탭하면 호스트 오브가 그 안으로 빨려 들어간다(합체 애니메이션, 클러스터 오브가 호스트 색으로 물든다). 이 상태에서 질문하면 그 클러스터의 코드가 컨텍스트로 들어간다.
   - **Undock(떼어내기)**: 클러스터 오브를 잡아당기거나(드래그 임계값) "나와" 하면 호스트 오브가 다시 분리되어 Siri형 오브로 나온다.
   - Tools: `locateCode`, `explainNode`, `summarizeCluster`, `reviewNode`, `planTour`. 가용 불가 시 `CodeSearcher`/`TourBuilder` 휴리스틱 폴백(기능은 유지, 문장이 단순해질 뿐).
4. **Voice Summon(음성 출두)** — "콘스텔(Constellate), @State를 쓰는 뷰 찾아줘" → SpeechAnalyzer → Host AI `locateCode` → 결과 노드에 **비콘**(바닥에서 솟는 빛기둥 + 링) 표시 + 해당 카드가 사용자 앞으로 **출두**(복제 카드가 날아와 손 앞에 멈춤, 원본 위치엔 실선 가이드). 모든 참가자에게 비콘이 동기화된다.
5. **Meeting(회의)** — GroupActivities(SharePlay, FaceTime)로 1명 이상 동시 접속. 역할: host 1 + member n. 모드: analysis / review(핀·코멘트) / lecture(가이드 투어, follow-host). 각 참가자는 "나의 모습" 아바타(스타일라이즈드 흉상형 마커 + 이름판 + 액센트 색)로 보인다. 레이저 포인터 공유.
6. **Theme(테마)** — `ConstellateTheme.dark` + `tinted(hue:)`. 규칙: 환경은 어둡고 탁하게(chroma ≤ 0.16, L ≤ 0.30), 코드는 밝고 선명하게(chroma ≥ 0.35, L ≥ 0.62), 환경 색상(hue)은 코드 팔레트 hue에서 20° 이상 떨어짐(자동 회피). `validate()`가 이를 검증하며 테스트로 강제된다.

## 플랫폼별 형태

| | visionOS | iPadOS | macOS |
|---|---|---|---|
| 별자리 | `ImmersiveSpace`(progressive 0.2…1.0) + RealityKit, 사용자가 원점 | 창 안 `RealityView` + 궤도 카메라(드래그/핀치) | 창 안 `RealityView` + 궤도 카메라(드래그/스크롤) |
| 호스트 오브 | 공간에 실물 크기 | RealityView 안 + 하단 캡슐 HUD | 동일 |
| 입력 | 시선+핀치, 손 드래그, 음성 | 터치, 펜슬, 음성 | 마우스, 키보드, 음성 |
| 회의 | SharePlay 공간 Persona | SharePlay | SharePlay |
| 창 | Dashboard 창(프로젝트 열기, 참가자, 테마, 다이얼) + 코드 인스펙터 창 | Split 3열(네비게이터/뷰포트/인스펙터) | 동일 + 메뉴바 명령 |

## 코드 팔레트(고정, 코드 전용) / 환경 팔레트(테마)

- 코드: plain `#F4F6FB`, keyword `#FF7AB6`, type `#5EE1FF`, function `#FFD166`, string `#B8FF7A`, number `#B89CFF`, comment `#8A93A6`, 카드 배경 `#0E1220 @78%`
- Dark 환경: skyTop `#05070F`, horizon `#121733`, floor `#0B0E1A`, grid `#2A3150`, 호스트 헤일로 `#9B8CFF`, 비콘 `#FFD166`, 하이라이트 `#5EE1FF`
- Tinted(hue H): sky `HSL(H,0.30,0.06)`~`HSL(H,0.34,0.17)`, 아바타 액센트 `HSL(H+180,0.6,0.68)`. 프리셋: Ocean 210°, Moss 150°, Ember 20°, Nebula 275°.
- 레이어 밴드: presentation cyan, domain lavender, data amber, infra grey, test lime.

## 3D 에셋(Blender 5.2, `/Applications/Blender.app`, 헤드리스 파이썬) → `Constellate/Resources/Assets3D/*.usdz`

| 파일 | 용도 | 비고 |
|---|---|---|
| `HostOrb.usdz` | 호스트 AI 오브 정적 형태(코어·밴드 4·셸). 애니메이션/발광은 앱이 코드로 | 반지름 0.12 m |
| `ClusterOrb.usdz` | 클러스터 오브 껍질(얇은 유리 + 내부 격자) | 반지름 0.18 m |
| `Avatar_Bust.usdz` | "나의 모습": 스타일라이즈드 흉상 + 이름판 링 | 높이 0.45 m, 액센트 머티리얼 슬롯 `Accent` |
| `Beacon.usdz` | 소환 비콘(빛기둥 + 2중 링) | 높이 3 m |
| `ReviewPin.usdz` | 리뷰 핀 | 0.08 m |
| `Stage_Ring.usdz` | 회의 스테이지 링(참가자 자리 6) | 반지름 1.2 m |
| `Pointer_Dart.usdz` | 레이저 포인터 끝 | 0.05 m |
| `NodeStars.usdz` | 노드 별 글리프 15종(역할 12 + 폴더 · 모듈 허브 + 순환 헤일로) | 0.1 m, 글리프당 ≤ 220 삼각형 |
| `Textures/FX_*.png` | 이펙트 스프라이트 6종(Glow · Spark · Ring · Beam · EdgeRamp · CardGlow), 흰 RGB + 알파 → 앱이 색을 입힘 | Cycles 렌더 |
| `Textures/Sky_Dark.png`, `Sky_Tint.png` | 등장방형 하늘(4096×2048). Tint는 그레이스케일 밝기 맵으로 앱이 hue를 곱함 | |
| `Textures/Floor_Grid.png` | 바닥 그리드 알파 | |
| `Blender/renders/*.png` | README·디자인 PRD용 렌더 | |

규칙: 에셋 색은 환경 팔레트 규칙을 따른다(코드와 겹치지 않도록 chroma 낮고 어두움; 발광 액센트만 테마 헤일로 색). 단위 미터, +Y up, 앞 -Z. 머티리얼 이름 고정(`Core`, `Band0`…`Band3`(호스트 오브 밴드별), `Shell`, `Accent`, `Glass`, `Base`)해서 앱이 교체 가능.

> 구현 메모(2026-10-19): 이 세션에는 Blender MCP 서버가 연결되어 있지 않아 `/Applications/Blender.app` 헤드리스 CLI(`Blender/scripts/build_all.py`)로 동일 파이프라인을 실행했다. MCP가 연결되면 같은 스크립트를 `execute_blender_code`로 실행하면 된다. 실제 스크립트/산출물 명세는 `PRD-Design-Constellate.md` §9–10 참조.

## 디렉터리

```
Constellate/
├─ Constellate.xcodeproj
├─ Constellate/                 # 앱 타깃(파일시스템 동기화 그룹)
│  ├─ App/  Scenes/  Views/  Spatial/  AI/  Voice/  Session/  Platform/
│  ├─ Resources/Assets3D/*.usdz  Resources/Textures/*.png
│  └─ Assets.xcassets
├─ ConstellateKit/              # 순수 Swift 패키지(Foundation+simd만), swift test
├─ Blender/scripts/*.py  Blender/renders/*.png
├─ Docs/  PRD-Tech-Constellate.md  TASKS-Constellate.md  PRD-Design-Constellate.md  VISION.md  diagrams/*.svg  images/*.png
└─ README.md
```
