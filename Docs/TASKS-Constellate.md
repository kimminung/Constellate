# Constellate — 태스크 문서 v1.2
PRD: `Docs/PRD-Tech-Constellate.md` (v1.0) · 디자인: `Docs/PRD-Design-Constellate.md` · 스펙: `Docs/VISION.md`
상태: **M0·M1·M2·M3 완료, M4·M5·M6 구현 완료(2차 라운드: 스트리밍 채팅·TTS·포인터 제스처·Accent 재틴트·핀 내보내기·follow-host 카메라), 실기기 미검증, M7 진행, M8 별자리 언어 v2(3차 라운드: 관계 11종·레이아웃 6종·노드 별·의존 분석·Blender v2 에셋/FX/하늘/바닥) — macOS 빌드·실행 확인(경고 0), iPadOS·visionOS 빌드 확인 대기 (2026-10-19)** · 기준 환경: **Xcode 27 / visionOS 27 · iPadOS 27 · macOS 27**
작성자: 김민웅(콜슨)

범례: 🔴 P0 (핵심 체험) / 🟡 P1 (완성도) / ⚪ P2 (여유 시)
상태: `[x]` 완료 · `[~]` 진행 중/부분 · `[ ]` 미착수
각 태스크는 독립 빌드·검증 가능한 단위. 순서 = 의존성 순서.
회귀 확인 명령은 문서 끝 "회귀 확인" 절 참조. 현재 결과: `swift test` **99 테스트 통과**(3차 라운드, Linux Swift 6.0.3에서 확인 — 앱이 쓰는 Kit 공개 API를 일반 `import`로 컴파일하는 `AppFacingAPITests` 포함), Xcode 27 macOS(My Mac) 빌드·실행 성공, **경고 0**(3차 라운드 전 35건 → 0, 2026-10-19), `Scripts/build.sh all`의 iPadOS·visionOS 시뮬레이터 빌드는 재확인 필요(T8.10).

---

## M0. 골격 · 계약 · 문서 (기반) — 완료

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T0.1 | 🔴 | [x] | Xcode 프로젝트 — 멀티플랫폼 단일 타깃(visionOS/iPadOS/macOS), Bundle ID `com.coulson.Constellate`, 파일시스템 동기화 그룹, 기본 MainActor 격리 + Approachable Concurrency, Swift 5 모드, `Constellate.entitlements`(`com.apple.developer.group-session`) | `Constellate.xcodeproj`, `Constellate/App/ConstellateApp.swift` | 3 플랫폼 스킴 존재, 앱 실행 |
| T0.2 | 🔴 | [x] | `ConstellateKit` 로컬 패키지 — Foundation + simd만, 테스트 타깃 + Fixtures 리소스 | `ConstellateKit/Package.swift` | `swift build` 성공 |
| T0.3 | 🔴 | [x] | Kit API 계약 — 모든 public 타입·시그니처 확정(CodeGraph·Layout·Theme·Cluster·Search·Tour·Session·Ingest·Sample) | `ConstellateKit/Sources/ConstellateKit/**` | 앱이 계약만으로 컴파일, 문서 §6 데이터 모델과 일치 |
| T0.4 | 🔴 | [x] | 테마 규칙 + 테스트 — `ConstellateTheme.validate()`(환경 6색 포함 floorGrid), `safeEnvironmentHue`, `RGBA` 변환, dark + 24 hue 검증 | `Theme/ConstellateTheme.swift`, `Tests/ThemeTests.swift` | 25 케이스 통과 |
| T0.5 | 🔴 | [x] | 공유 스펙 VISION v0.1 | `Docs/VISION.md` | 모든 에이전트가 참조하는 단일 소스 |
| T0.6 | 🔴 | [x] | 문서 3종 + 다이어그램 — Tech PRD, Design PRD, TASKS, SVG 5종(+PNG), README, LICENSE | `Docs/PRD-*.md`, `Docs/TASKS-Constellate.md`, `Docs/diagrams/*.svg|png`, `README.md`, `LICENSE` | `xmllint --noout` 통과, 링크 경로 유효 |
| T0.7 | 🔴 | [x] | Blender 에셋 파이프라인 — 헤드리스 CLI로 USDZ 7종 + 텍스처 3종 + 렌더 10종 + 앱 아이콘 | `Blender/scripts/{constellate_lib,build_assets,build_textures,render_assets,build_all}.py`, `make_icon_set.sh`, `README.md` | `build_all.py` 1회 실행으로 `Resources/Assets3D/*.usdz`(7, `usdchecker --arkit` 통과), `Resources/Textures/*.png`(3), `Blender/renders/*.png`(10), `AppIcon-1024.png` 생성 |
| T0.8 | 🔴 | [x] | 빌드 스크립트 + 첫 3 플랫폼 빌드 — 모듈 캐시 재지정, 경고 필터 | `Scripts/build.sh` | `Scripts/build.sh all` 3회 `exit=0` |

## M1. ConstellateKit 실구현 (데이터의 뼈대) — 완료

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T1.1 | 🔴 | [x] | `SwiftSymbolExtractor` — 문자열/주석 스트리핑 → 라인+브레이스 스캔. struct/class/enum/actor/protocol/extension/func/var·let, 상속 목록, 중첩 parentName, imports, referencedTypeNames, 태그 | `Ingest/SwiftSymbolExtractor.swift`, `Tests/ExtractorTests.swift`(8), `Tests/Fixtures/` | 픽스처에서 심볼 수·라인 범위·상속·태그 기대값 일치 |
| T1.2 | 🔴 | [x] | `ProjectIngestor` — 폴더 워크(제외 디렉터리·확장자·크기·`maxFiles` 캡), 노드 ID `path#Symbol`, 레이어 추론, `modifiedAt` 상속, 관계 엣지 4종, 진행률·취소 | `Ingest/ProjectIngestor.swift`, `Tests/IngestorTests.swift`(5) | 임시 디렉터리 인제스트 → 노드/엣지 수·레이어·캡 검증 |
| T1.3 | 🔴 | [x] | `RadialShellLayout` — PRD §5.2 알고리즘(가중치·섹터 분할·셸 반지름·레이어 y+지터·w 정규화·`radius = clamp(0.08 + √lines/90, 0.08, 0.32)`·가장 가까운 공간 조상 상속·경계) | `Layout/RadialShellLayout.swift`, `Tests/LayoutTests.swift`(9) | (a) 자식 섹터 ⊂ 부모 (b) 형제 비겹침 (c) 반지름 식 (d) dial 0 항등 (e) 투영 연속 (f) 결정성 |
| T1.4 | 🔴 | [x] | `ClusterBuilder` — folder/file/type/feature 4 그래뉼래리티, `dominantLayer`, `totalLines`, `heuristicSummary` | `Cluster/ClusterBuilder.swift`, `Tests/ClusterTests.swift`(6) | OrbitNotes에서 그래뉼래리티별 클러스터 수·멤버 포함 검증 |
| T1.5 | 🔴 | [x] | `CodeSearcher` — 퍼지 이름/경로, kind 단어, 태그 구문, 구조 구문(inherits/conforms/imports/uses/in folder), 한국어 동의어, 점수·reason, `explainQuery` | `Search/CodeSearcher.swift`, `Tests/SearchTests.swift`(12) | EN/KO 질의 기대 상위 1건 일치 |
| T1.6 | 🔴 | [x] | `TourBuilder` — 엔트리 포인트 → 루트 타입 → 바쁜 파일, `candidates(for:maxSteps:)` 분리(AI가 내레이션만 생성) | `Tour/TourBuilder.swift`, `Tests/TourTests.swift`(3) | 8 스텝, 첫 스텝 = `@main`, 중복 없음 |
| T1.7 | 🔴 | [x] | `SampleGraph.orbitNotes()` — 47 파일 · 15 폴더 · 50+ 타입 SwiftUI 앱(레이어 5종, imports/inherits/references, 수정일 분포) | `Sample/SampleGraph.swift`, `Tests/SampleGraphTests.swift`(4) | 파일 ≥ 40, 레이어 전부 등장, 레이아웃 셸 ≥ 4 |
| T1.8 | 🟡 | [x] | `GraphDigest` + `ConstellateMessage`·`ConstellateTheme`·`CodeGraph` JSON 라운드트립 | `Tests/CodableTests.swift`(5) | 인코딩 → 디코딩 동치 |
| T1.9 | 🟡 | [x] | `CodeGraph+Analysis` — `GraphStats`, `stats()`, `hubs()`, `entryPoints()`, `fanIn(of:)`, `busiestFiles()`, `subtreeLines(of:)` (AI 프롬프트·투어·Dashboard 통계 근거) | `Graph/CodeGraph+Analysis.swift` | SampleGraph 테스트에서 통계 기대값 |
| T1.10 | ⚪ | [~] | 오픈 이슈 반영 — O4(floorGrid 규칙 포함, S 0.26) ✔ · O5(가장 가까운 공간 조상) ✔ · O3(Package 플랫폼/언어 모드 통일) 미결 | `Theme/ConstellateTheme.swift`, `Layout/RadialShellLayout.swift`, `Package.swift` | O3 결정 후 테스트 갱신 |
| T1.11 | 🟡 | [ ] | 인제스트 디스크 캐시 — `CodeGraph` JSON 저장/로드 + 수정일 무효화(앱 측, FR-1.11) | `App/AppModel+Cache.swift` | 4000 파일 그래프 로드 ≤ 300 ms |

**완료 기준 충족**: `swift test` 54/54, OrbitNotes가 PRD G2 조건을 만족.

## M2. 별자리 씬 (공간의 뼈대) — 완료(시뮬레이터)

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T2.1 | 🔴 | [x] | `AppModel` — graph/layout/clusters/theme/timeDial/granularity/selection 상태, 인제스트 Task(백그라운드 → MainActor 홉), 샘플 자동 로드 | `App/AppModel.swift` | 샘플 로드 후 placements > 0 |
| T2.2 | 🔴 | [x] | `EnvironmentEntity` — 스카이돔(`Sky_Dark.png` / `Sky_Tint.png` × hue), 바닥 `Floor_Grid.png`, 안개, 테마 적용 | `Spatial/EnvironmentEntity.swift` | 5 프리셋 전환 시 코드 가독 유지(`screenshot-ipad-ocean.png`) |
| T2.3 | 🔴 | [x] | `MeshFactory` + `TextureFactory` — 카드 메시, 비동기 카드 텍스처(전용 400장 캡), 솔리드 폴백 | `Spatial/MeshFactory.swift`, `Spatial/TextureFactory.swift` | OrbitNotes 카드 전부 표시 |
| T2.4 | 🔴 | [x] | `EdgeRenderer` — contains 실선 + 관계 엣지 4종 색, weight 상위 1500 캡, 파티클 | `Spatial/EdgeRenderer.swift` | 1500 엣지 표시 |
| T2.5 | 🔴 | [x] | `ConstellationSceneController` + `CodeNodeEntity` — 카드·엣지·오브 배치, `position3(timeDial:)` 적용, 선택/하이라이트, 노드 캡 2500 | `Spatial/ConstellationSceneController.swift`, `Spatial/CodeNodeEntity.swift` | 샘플 별자리 3 플랫폼 표시 |
| T2.6 | 🔴 | [x] | `OrbitCameraRig` + `ConstellationViewport`(iPad/mac) — 드래그 회전·핀치/스크롤(`ScrollWheelMonitor`) 줌·팬·리셋 | `Platform/OrbitCameraRig.swift`, `Platform/ConstellationViewport.swift`, `Platform/ScrollWheelMonitor.swift` | 제스처 동작(`screenshot-ipad*.png`) |
| T2.7 | 🔴 | [x] | visionOS `ConstellationImmersiveView` + `HeadPoseProvider` — progressive 이머시브, 사용자 원점 | `Platform/ConstellationImmersiveView.swift`, `Platform/HeadPoseProvider.swift` | 시뮬레이터 진입/이탈(`screenshot-visionos-dashboard.png`) |
| T2.8 | 🔴 | [x] | `TimeDialView` — 연속 투영, 쓰로틀 | `Views/TimeDialView.swift` | −1…1 스냅 없음 |
| T2.9 | 🔴 | [x] | `ThemePickerView` · `DashboardView` — 프리셋 5 + hue, 그래뉼래리티·모드 | `Views/ThemePickerView.swift`, `Views/DashboardView.swift` | 전환 반영 |
| T2.10 | 🟡 | [ ] | 레이어 밴드 이중 부호화(색 + SF Symbol 아이콘 링) | `Spatial/LayerBandRing.swift` | 색약 시뮬레이션에서 구분 |
| T2.11 | 🟡 | [ ] | 그래뉼래리티 전환 애니메이션(카드 → 오브 수렴 0.6 s) | `Spatial/ConstellationSceneController+Granularity.swift` | 4 모드 전환 끊김 없음 |

## M3. 오브 · 클러스터 · 인스펙터 — 구현 완료

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T3.1 | 🔴 | [x] | `OrbEntity` — `HostOrb.usdz`/`ClusterOrb.usdz` 로드(`AssetLoader`), 머티리얼 교체(`Core`/`Band0…3`/`Shell`/`Glass`), Presence 에너지 → 발광·회전·파티클, 프로시저럴 폴백 | `Spatial/OrbEntity.swift`, `Spatial/AssetLoader.swift` | 에너지 4단계 시각 차이 |
| T3.2 | 🔴 | [x] | 클러스터 오브 — centroid 배치, dominantLayer 틴트, 탭 expand/collapse | `Spatial/ConstellationSceneController.swift` | expand 시 카드가 원위치로 |
| T3.3 | 🔴 | [x] | 호스트 오브 Free 상태 — 사용자 앞 0.9 m(visionOS 머리 추종), iPad/mac은 카메라 앞 | `Spatial/OrbEntity.swift`, `Platform/HeadPoseProvider.swift` | 추종 확인 |
| T3.4 | 🔴 | [x] | Dock/Undock 상태기계 + 모션, `orbDock` 브로드캐스트 | `Spatial/OrbEntity.swift`, `App/AppModel.swift` | 탭 dock, 드래그/음성 undock |
| T3.5 | 🔴 | [x] | `InspectorView` + `CodeInspectorWindow` — 경로·레이어·라인·관계 in/out·코드 전문(`SyntaxHighlighter`, `SourceProvider`)·핀 | `Views/InspectorView.swift`, `Support/SyntaxHighlighter.swift`, `Support/SourceProvider.swift` | 노드 선택 → 인스펙터 갱신(`screenshot-ipad-inspector.png`) |
| T3.6 | 🔴 | [x] | `NavigatorView` — 트리/클러스터/핀, 선택 동기화, 검색(`CodeSearcher`) | `Views/NavigatorView.swift` | 트리 선택 ↔ 씬 하이라이트 |
| T3.7 | 🔴 | [x] | `CodeCardView` — 2D 카드(iPad/mac 인스펙터·소환 미리보기) | `Views/CodeCardView.swift` | CodePalette 구문색 |
| T3.8 | 🟡 | [x] | `VoiceButton` · HUD 요소 — 오브 상태·마이크·다이얼 | `Views/VoiceButton.swift`, `Views/DashboardView.swift` | 상태 변화 반영 |
| T3.9 | ⚪ | [ ] | 캘리그램 expand 연출(글자 흐름 0.8 s) | — | reduce motion 시 크로스페이드 |

## M4. 호스트 AI — 구현 완료(채팅 스트리밍 포함), 실기기 미검증

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T4.1 | 🔴 | [x] | `HostAI` — 가용성 관찰, `LanguageModelSession` 생성·prewarm, 상태(idle/listening/thinking/speaking), 오브 연동 | `AI/HostAI.swift` | 가용/불가 두 경로 UI |
| T4.2 | 🔴 | [x] | Instructions 빌드 — 프로젝트 통계(`GraphStats`)·레이어 분포·선택/도킹 컨텍스트·언어, 절단 | `AI/HostAI.swift` | 컨텍스트 예산 내 |
| T4.3 | 🔴 | [x] | Tools 5종 — `LocateCode`, `ExplainNode`, `SummarizeCluster`, `ReviewNode`, `PlanTour` (`@Generable` 인자) | `AI/HostAI.swift` | 그래프 조회 결과 반환 |
| T4.4 | 🔴 | [x] | `@Generable` 응답 — `LocateAnswer{speech, nodeIDs}`, `TourAnswer{title, steps}` → 하이라이트/소환/투어 실행 | `AI/HostAI.swift` | 응답 → 씬 반영 |
| T4.5 | 🔴 | [x] | `HeuristicHost` 폴백 — 동일 인텐트를 CodeSearcher/heuristicSummary/TourBuilder로, 배지 | `AI/HeuristicHost.swift` | 시뮬레이터에서 5 인텐트 응답(`screenshot-ipad-summon.png`) |
| T4.6 | 🔴 | [x] | 컨텍스트 초과 복구 — 새 세션 재시도 → 폴백 | `AI/HostAI.swift` | 복구 경로 존재 |
| T4.7 | 🟡 | [~] | **스트리밍 응답** — 자유 채팅은 `HostAI.streamChat`(`LanguageModelSession.streamResponse`, 부분 갱신 ≤ 15 Hz)로 말풍선 타이핑 ✔; explain/review/summarize 도구 응답은 아직 일괄 표시(T4.10) | `AI/HostAI.swift`, `Views/HostChatView.swift` | 채팅 부분 텍스트 표시 ✔ |
| T4.10 | 🟡 | [ ] | 도구 응답 스트리밍 — `LocateAnswer`/`TourAnswer` 부분 생성(`PartiallyGenerated`) 처리 후 explain/review/summarize도 스트리밍 | `AI/HostAI.swift` | 도구 응답 타이핑 표시 |
| T4.8 | 🟡 | [~] | 가드레일 거부 처리 — 오류 메시지 표시, 전용 문구/Idle 복귀 다듬기 필요 | `AI/HostAI.swift` | 거부 시 안내 + Idle |
| T4.9 | 🔴 | [ ] | **실기기 검증**(Vision Pro / M-시리즈 Mac, Apple Intelligence ON) — 5 도구 실호출 로그 | `Docs/images/ai-tools-log.png` | 성공 캡처 |

## M5. 음성 출두 — 구현 완료(TTS 포함), 실기기 미검증

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T5.1 | 🔴 | [x] | `SpeechListener` — `AVAudioEngine` 탭 → `SpeechAnalyzer`/`SpeechTranscriber`, 권한 안내, 스트림 | `Voice/SpeechListener.swift` | 시뮬레이터에서 가용성 분기 확인 |
| T5.2 | 🔴 | [x] | 웨이크워드 "Constellate"/"콘스텔" + 수동 Listening(`VoiceButton`) | `Voice/SpeechListener.swift`, `Views/VoiceButton.swift` | 감지 → Listening |
| T5.3 | 🔴 | [x] | `VoiceCommandRouter` — `parse(_:) -> VoiceIntent`(find/explain/summarize/review/tour/undock/follow/free) | `Voice/VoiceCommandRouter.swift` | 인텐트 라우팅 |
| T5.4 | 🔴 | [x] | `BeaconEntity` — `Beacon.usdz` + 테마 `beacon` 색, 등장/해제 | `Spatial/BeaconEntity.swift` | 비콘 표시·제거 |
| T5.5 | 🔴 | [x] | 소환(summon) — 복제 카드 → 사용자 앞, 가이드선, 해제 복귀, 하이라이트 링 | `Spatial/ConstellationSceneController.swift` | `screenshot-ipad-summon.png` |
| T5.6 | 🔴 | [x] | 텍스트 입력 폴백 — `HostChatView`가 동일 라우터 사용 | `Views/HostChatView.swift` | 시뮬레이터 전 인텐트 동작 |
| T5.7 | 🟡 | [x] | TTS `HostVoice` — `AVSpeechSynthesizer`, ko-KR/en-US 자동 선택, "Speak replies · 음성 읽기" 토글(영구 저장), `Presence.speaking`을 실제 발화 구간에 연동 | `Voice/HostVoice.swift` | 발화 중 에너지 0.75 ✔ |
| T5.8 | 🔴 | [ ] | **실기기 검증** — "콘스텔, @State를 쓰는 뷰 찾아줘" → 비콘 + 복제 카드 | `Docs/images/summon-device.png` | 캡처 |
| T5.9 | 🟡 | [ ] | `installTap` deprecation 경고 제거 — 새 `AVAudioInputNode` 비동기 API로 교체 | `Voice/SpeechListener.swift` | 경고 0 |

## M6. 회의 (GroupActivities) — 구현 완료(시뮬레이션 멤버), 2기기 미검증

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T6.1 | 🔴 | [x] | `ConstellateActivity` + `SessionCoordinator` — 세션 수명주기, `GroupSessionMessenger` JSON, 역할 결정, 솔로 모드, 시뮬레이션 멤버 | `Session/ConstellateActivity.swift`, `Session/SessionCoordinator.swift`, `Constellate.entitlements` | 로컬 시뮬레이션 멤버로 메시지 라운드트립(`screenshot-ipad-meeting.png`) |
| T6.2 | 🔴 | [~] | 핸드셰이크 — hello → roster/graphDigest/theme/timeDial/mode; 체크섬 불일치 시 그래프 구조 청크 전송은 **미구현** | `Session/SessionCoordinator.swift` | 4000 파일 전송 ≤ 5 s, 소스 본문 미포함 |
| T6.3 | 🔴 | [x] | `hostSpeech ask:` 규약 — member 질문 전달, host만 AI 수행, 답변 브로드캐스트 | `Session/SessionCoordinator.swift` | member 질문 → host 답변 |
| T6.4 | 🔴 | [x] | 역할 권한 — 테마/다이얼/모드/투어는 host만 | `Views/*`, `App/AppModel.swift` | member에서 제어 비활성 |
| T6.5 | 🔴 | [x] | follow-host — `followHost` 상태 반영, 원격 `.summon`/`.tourStep` 수신 시 iPad/Mac 궤도 카메라가 해당 노드로 비행(거리 3.5 m), visionOS는 카메라 대신 발광 가이드 화살표 표시 | `Session/SessionCoordinator.swift`, `Platform/OrbitCameraRig.swift`, `Spatial/ConstellationSceneController.swift` | 로컬 시뮬레이션 멤버로 확인; 2기기는 T6.11 |
| T6.6 | 🔴 | [x] | 레이저 포인터 — iPad/Mac: 0.35 s 길게 누르기 + 드래그 → 카메라 레이 + `Scene.raycast`(실패 시 평면 폴백); visionOS: 스카이돔 위 핀치 유지. `.pointer` ≤ 10 Hz 브로드캐스트, `Pointer_Dart` 표시. **주의**: 손을 떼도 해제 메시지를 보내지 않아 원격 다트가 마지막 위치에 남음(T6.13) | `Spatial/ConstellationSceneController.swift`, `Platform/ConstellationViewport.swift`, `Platform/ConstellationImmersiveView.swift` | 상대 기기에 다트 표시 ✔ |
| T6.7 | 🔴 | [x] | 리뷰 핀 — 작성·`pin`/`resolvePin` 동기화·`ReviewPin` 표시·인스펙터 목록, resolve/삭제(host 또는 작성자; 삭제는 `.resolvePin(resolved: true)`로 전파), **Markdown 내보내기** `PinsExporter`(iPad/visionOS `ShareLink`, macOS `fileExporter`) | `Session/SessionCoordinator.swift`, `Views/InspectorView.swift`, `Support/PinsExporter.swift` | 핀 동기화 + 내보내기 파일 ✔ |
| T6.8 | 🔴 | [x] | 가이드 투어 — `tour`/`tourStep` 전파, host 전진/후진, 스텝 비콘 + 내레이션 | `Views/TourBarView.swift` | 시나리오 C 로컬 완주 |
| T6.9 | 🔴 | [x] | 아바타 — `Avatar_Bust.usdz` + 이름판, `Stage_Ring.usdz` 배치, `ParticipantsView` | `Spatial/AvatarEntity.swift`, `Views/ParticipantsView.swift` | 참가자 수만큼 흉상 |
| T6.10 | 🟡 | [ ] | 세션 종료 처리(host 이탈 안내), 재접속 | `Session/SessionCoordinator.swift` | 안내 표시 |
| T6.11 | 🔴 | [ ] | **2기기 실기 검증** — 시나리오 A/B/C, 라운드트립 측정 | `Docs/images/session-*.png` | ≤ 300 ms 기록 |
| T6.12 | 🟡 | [x] | USDZ `Accent` 런타임 재틴트 — `AssetLoader.retintAccent(in:color:)`: 머티리얼/엔티티 이름 또는 색 매칭으로 `Accent` 슬롯을 참가자 액센트로 교체 | `Spatial/AssetLoader.swift` | 참가자별 흉상 색 차이 ✔ |
| T6.13 | 🟡 | [ ] | 포인터 해제 메시지 — 손을 뗄 때 원격 다트를 지우는 신호(예: `pointer`에 `nil`/sentinel 위치 또는 수신 측 타임아웃 0.5 s 적용) | `Session/SessionCoordinator.swift`, `Spatial/ConstellationSceneController.swift` | 해제 후 원격 다트 사라짐 |
| T6.14 | ⚪ | [x] | `screenshotMode` 디버그 토글 — 캡처용으로 HUD/디버그 요소 정리 | `App/AppModel.swift` | 토글 시 캡처 친화 화면 |

## M7. 마무리 · 검증 — 진행 중

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T7.1 | 🔴 | [ ] | 성능 측정 — NFR-1 표 전 항목(인제스트 4000 파일, 레이아웃, 엣지 1500, 90 fps visionOS 실기, 메모리) | `Docs/PERF.md` | 측정치 기록 |
| T7.2 | 🔴 | [ ] | 접근성 — VoiceOver 라벨, Dynamic Type, Reduce Motion, 색약 이중 부호화 점검 | 체크리스트 | 3 플랫폼 점검 |
| T7.3 | 🔴 | [ ] | **macOS 스크린샷** — 이번 세션의 셸에 화면 기록 권한이 없어 캡처 실패. 권한 부여 후 재시도 | `Docs/images/screenshot-macos.png` | README 반영 |
| T7.4 | 🟡 | [x] | visionOS·iPad 스크린샷 — Vision Pro 시뮬레이터 Dashboard, iPad 세로/가로/인스펙터/회의/Ocean/소환 | `Docs/images/screenshot-visionos-dashboard.png`, `screenshot-ipad.png`, `screenshot-ipad-landscape.png`, `screenshot-ipad-inspector.png`, `screenshot-ipad-meeting.png`, `screenshot-ipad-ocean.png`, `screenshot-ipad-summon.png` | README 갤러리 |
| T7.5 | 🟡 | [~] | 히어로 이미지 합성 | `Docs/images/hero.png` | README 최상단 |
| T7.6 | 🟡 | [x] | 에셋 최종 — 머티리얼 슬롯(`Core`, `Band0…3`, `Shell`, `Accent`, `Glass`, `Base`), 삼각형 < 20k, `usdchecker --arkit`, 렌더 10종, 앱 아이콘 | `Resources/Assets3D/*.usdz`, `Blender/renders/*.png`, `Assets.xcassets/AppIcon.appiconset/*` | Design PRD §9 표 일치. 남은 것: MCP 경로 교차 검증(이번 세션 MCP 미연결) |
| T7.7 | 🟡 | [ ] | 상태 복원(북마크·테마·다이얼) | `App/AppModel+Persistence.swift` | 재실행 복원 |
| T7.8 | ⚪ | [ ] | 온보딩 오버레이(첫 실행: 웨이크워드·dock·다이얼 안내) | `Views/Onboarding.swift` | 1회 표시 |

## M8. 별자리 언어 v2 — 관계 · 레이아웃 · 에셋 (2026-10-19 3차 라운드)

목표: 그래프를 "납작한 원반 + 회색 선"에서 **여러 차원을 동시에 읽히는 별자리**로 — 모양(레이아웃 스타일)·관계의 의미(종류·방향·흐름)·노드의 역할과 결합도·의존 순환을 한 공간에서. 그래프 형태는 CoulsonPortfolioWeb `Public/js/space/`(relations.js, layouts/*)를 최대한 포팅했다.

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T8.1 | 🔴 | [x] | 관계 의미 모델 — `RelationKind` 11종(포트폴리오 `EDGE_TYPES`: 색·점선·flow·lane·altitude·priority·KO/EN 라벨), `CodeRole` 12종(`ROLES`·`inferRole`), `CodeEdge.relation` / `CodeNode.role`(Codable 하위 호환) | `Graph/RelationKind.swift`, `Graph/CodeGraph.swift` | `RelationTests` |
| T8.2 | 🔴 | [x] | 관계 분류기 — 바인딩 래퍼·프레젠테이션 문맥·생성·알림 post/observe·delegate/datasource, extension → `extends`, 인제스트·샘플 그래프에 적용 | `Ingest/RelationClassifier.swift`, `SwiftSymbolExtractor`, `ProjectIngestor`, `SampleGraph` | Constellate 자신(97 파일) 도그푸딩: uses 258 · creates 101 · imports 42 · binds 20 · composes 11 · extends 6 · presents 5 |
| T8.3 | 🔴 | [x] | 레이아웃 스타일 6종 — `.celestial`(신규 기본: 깊이 = 거리, 서브트리 = 방위, 레이어 = 고도각, 최근 = 바깥) + 포트폴리오 포팅 `.sphere` `.treeRadial` `.wall` `.spiral` + v1 `.shells`; 스타일별 시간 투영(구면/원통), `boundingSphere` | `Layout/{LayoutStyle,LayoutContext,SphereLayout,TreeRadialLayout,WallLayout,SpiralLayout}.swift`, `RadialShellLayout`, `ConstellationLayout` | `LayoutStyleTests`: 모든 노드 배치 · 카드 비겹침 · 바닥 여유 · 결정성 |
| T8.4 | 🔴 | [x] | 엣지 씬 빌더 — 2차 베지어 + lane 회전, 점선, 화살촉, flow 경로, off/focus/all, 범례 숨김, 예산(1500/600/2500/240), 포커스 확장·`related`, 순환 강조, 평행 이동 프레임 튜브 메시 | `Geometry/EdgeScene.swift` | `EdgeSceneTests`, 샘플 빌드 ~43 ms(release) |
| T8.5 | 🔴 | [x] | 의존 분석 — 파일 단위 의존, 반복형 Tarjan 순환, impact/reach, Martin 지표, 값싼 `fanIn/fanOut`, `cycleMembers` | `Graph/GraphInsights.swift` | `RelationTests`, `InspectorDigestTests` |
| T8.6 | 🟡 | [x] | 노드 별 인코딩 + 인스펙터 다이제스트 — `StarEncoder`(모양·색·크기·발광·헤일로·`anchor`), `RelationDigest`(종류 × 방향 그룹, 멤버 접기, KO/EN 문구), `ConstellationSnapshot`(+범례) | `Geometry/NodeStars.swift`, `Graph/RelationDigest.swift`, `Geometry/ConstellationSnapshot.swift` | `StarEncoderTests`, `InspectorDigestTests`, `SnapshotTests` |
| T8.7 | 🔴 | [x] | Blender v2 에셋 "관측 기기" — 7종 재디자인(혼천의 호스트 오브 등), `NodeStars.usdz` 15 글리프, FX 스프라이트 6종(`Field` 수식 → Cycles → 선형 EXR → 알파) | `Blender/scripts/{build_assets,build_graph_assets,constellate_lib}.py`, `Resources/Assets3D/*.usdz`(8), `Resources/Textures/FX_*.png`(6) | 8 USDZ ARKit 규칙 통과, 예산 내 |
| T8.8 | 🟡 | [x] | 환경 텍스처 v2 — 은하수·별 등급 4단계·성운 2층 하늘(L ≤ 0.29, chroma ≤ 0.06), 셸 반지름에 맞춘 아스트롤라베 바닥 | `build_textures.py`, `Sky_Dark/Sky_Tint/Floor_Grid.png` | 테마 규칙 측정 통과 |
| T8.9 | 🟡 | [x] | 별자리 렌더 — Kit 스냅샷 JSON으로 레이아웃 6종 + 사용자 시점 + 갤러리 + 별/관계 범례 | `render_graph.py`, `Blender/data/*.json`, `Blender/renders/{layout_*,node_stars,relation_legend}.png` | README·PRD 갤러리 |
| T8.10 | 🔴 | [~] | 앱 통합 — `AppModel`(layoutStyle·relationMode·hiddenRelations 영속, insights, `relationSummary` → 호스트 AI 문맥), `EdgeRenderer`(Kit 빌더 + `FX_EdgeRamp` 튜브 + `FlowParticles`), `NodeStarFactory`, `FXTextures`, 카드 역할 칩·결합도 부제·`FX_CardGlow` 선택·포커스 디밍·순환 헤일로, 비콘 `FX_Ring`/`FX_Beam`, 오브 오라 `FX_Glow`, 레이아웃 피커·관계 모드·범례(대시보드·툴바·⌘L·⌃⌘1…6 메뉴), 인스펙터 결합도·관계 그룹, SharePlay `.layoutStyle` / `.relationMode` | `App/`, `Spatial/`, `Views/RelationLegendView.swift`, `InspectorView`, `DashboardView`, `Session/SessionCoordinator` | 독립 리뷰(교차 모듈 컴파일 프로브) 반영: `EdgeScene` 공개 init(컴파일 오류), 재빌드 뒤 선택·하이라이트·핀·비콘·소환 재적용, 취소된 빌드의 중복 카드, 하이라이트 후 디밍 갱신·선택 내용물 비디밍, 레이아웃/설치/클러스터 세대 토큰, 빌드 중 테마 변경, 선택 엣지 재빌드 60 ms 디바운스, 하늘 우선 로드(+첫 rebuild 테마 재적용), 재빌드 시 소환 복제 유지(가이드만 이동), 틴트→다크 하늘 경쟁, 핀 배치(별 오른쪽·미터 단위·핀 에셋 이중 축소 수정) — 2차 재검토로 확인 · Xcode macOS 빌드·실행 확인(경고 0, 인스펙터 결합도·관계 그룹·포커스 디밍 동작 확인) · **남은 것: iPadOS·visionOS 시뮬레이터 빌드(`Scripts/build.sh all`)와 육안 점검** |
| T8.11 | 🟡 | [ ] | 성능 확인 — 2500 카드 + 별 1200 + 튜브 1500 + 파티클 240에서 visionOS 90 fps, 엣지 재빌드(선택 변경마다) 지연 | 측정 | NFR-1 표 |
| T8.12 | ⚪ | [ ] | 앱 아이콘 재렌더 — 아이콘은 v1 호스트 오브 그대로(`render_icons.py` 미실행) | `Assets.xcassets/AppIcon*` | 결정 후 |
| T8.13 | 🟡 | [x] | 관계 검색 — `CodeSearcher`가 "presents X" / "observed by X" / "X를 띄우는" 등 관계 구문을 제약으로 해석(대상이 그래프에 없으면 자유 텍스트로 강등), 호스트 AI `locateCode` 설명·`explainNode` 문맥에 관계 다이제스트 | `Search/CodeSearcher.swift`, `AI/HostAI.swift` | `RelationSearchTests` |
| T8.14 | 🟡 | [x] | 앱 대면 API 가드 — Kit의 다른 테스트는 `@testable import`라 `internal` 누락을 못 잡는다. 일반 `import`로 앱이 호출하는 v2 API(관계 레이어·별·인스펙터·범례·세션 메시지)를 컴파일·호출하는 스위트 | `Tests/ConstellateKitTests/AppFacingAPITests.swift` | Xcode 없이 리눅스 `swift test`에서 접근 수준 회귀 검출 |

---

## 알려진 갭 (2026-10-19 2차 라운드 후, 솔직한 목록)

해결됨(2차 라운드): 채팅 스트리밍(T4.7) · TTS(T5.7) · 포인터 제스처(T6.6) · `Accent` 재틴트(T6.12) · 핀 resolve/삭제/Markdown 내보내기(T6.7) · follow-host 카메라 비행/가이드 화살표(T6.5).

| 갭 | 영향 | 태스크 |
|---|---|---|
| 도구 응답(explain/review/summarize) 스트리밍 없음 — 자유 채팅만 스트리밍 | 도구 응답은 완성 후 일괄 표시 | T4.10 |
| 포인터 해제 메시지 없음 | 손을 떼도 원격 다트가 마지막 위치에 남음 | T6.13 |
| 그래프 구조 청크 전송 미구현 | 같은 프로젝트가 없는 member는 별자리를 못 받음(샘플은 공유) | T6.2 |
| 씬 노드 캡 2500 / 전용 텍스처 400 | 대형 레포는 상위 가중치만 카드, 나머지는 폴더에 접힘/솔리드 | NFR-1.4(의도된 예산) |
| `AVAudioEngine.installTap` deprecation 경고 1건 | 빌드 경고 | T5.9 |
| 실기기 검증 미실시 — Vision Pro, 2기기 SharePlay, Apple Intelligence 실응답 | 시뮬레이터 폴백 경로만 확인됨 | T4.9 · T5.8 · T6.11 |
| macOS 스크린샷 없음(화면 기록 권한) | README 갤러리에 macOS 누락 | T7.3 |
| Blender MCP 미연결(CLI만 사용) | MCP 경로 산출물 동일성 미검증 | T7.6 |
| 3차 라운드 앱 코드는 macOS로만 빌드 확인 — `#if os(visionOS)`·UIKit 분기(비전 대시보드 별자리 패널, 파티클 Billboard, iPad ⌘L 단축키, Reduce Motion)는 아직 컴파일되지 않음 | iPadOS·visionOS 첫 빌드에서 사소한 오류가 나올 수 있음 | T8.10 |
| 선택이 바뀔 때마다 관계 메시 전체 재빌드(백그라운드, 60 ms 디바운스로 연속 클릭은 1회로 합침) | 대형 그래프에서 포커스 반응 지연 가능(메시 생성은 메인 액터) | T8.11 |
| 별 글리프 = 카드당 엔티티 1개(최대 1200) | 드로콜 증가 | T8.11 |

## 의존성 요약

```
M0 ─→ M1 (Kit) ─→ M2 (씬) ─→ M3 (오브·인스펙터) ─→ M4 (호스트 AI) ─→ M5 (음성 출두) ─→ M6 (회의) ─→ M7
            └─ T0.7 에셋은 M3·M5·M6에서 소비 (없으면 프로시저럴 폴백)
            └─ 실기기 검증(T4.9·T5.8·T6.11)은 한 세션에 묶어서 수행
```

## 검증 매트릭스

| 기능 | visionOS 시뮬 | visionOS 실기 | iPad 시뮬 | macOS | 비고 |
|---|---|---|---|---|---|
| 샘플 별자리 표시 | [x] | [ ] | [x] | [x] (빌드·실행; 캡처 대기) | T2.5 |
| 폴더 인제스트(4000 파일) | — | [ ] | [ ] | [ ] | 성능 측정은 T7.1 |
| 타임 다이얼 연속성 | [x] | [ ] | [x] | [x] | T2.8 |
| 테마 5 프리셋 | [x] | [ ] | [x] | [x] | `screenshot-ipad-ocean.png` |
| dock / undock | [x] | [ ] | [x] | [x] | T3.4 |
| 호스트 AI 도구 5종 | 폴백만 | [ ] | 폴백만 | [ ] (Apple Intelligence ON) | T4.9 |
| 음성 출두 | 텍스트만 | [ ] | 텍스트만 | [ ] | T5.8 |
| SharePlay 3 모드 | 시뮬 멤버 | [ ] | 시뮬 멤버 | [ ] | T6.11, 2기기 |
| 90 / 60 fps | — | [ ] | [ ] | [ ] | T7.1 |
| 접근성 점검 | [ ] | [ ] | [ ] | [ ] | T7.2 |

## 회귀 확인

변경 후 항상 아래 두 명령을 실행한다(순서대로). 둘 다 성공해야 커밋한다.
**주의**: `Scripts/build.sh`의 캐시 경로가 한때 상대 경로 `~/`로 풀려 저장소 안에 `~/Library/Caches/ConstellateBuild` 폴더가 생성·커밋된 적이 있다(main에서 제거, `.gitignore`에 추가됨). 커밋 전 `git status`에 `~/` 디렉터리가 보이면 추가하지 말 것.

```sh
cd ConstellateKit && swift test          # Kit 단위 테스트 — 현재 99 테스트 통과 (AppFacingAPITests = 앱 대면 공개 API 가드)
Scripts/build.sh all                     # macOS · iPadOS 시뮬레이터 · visionOS 시뮬레이터 3 빌드, 각 exit=0
```

보조:

```sh
for f in Docs/diagrams/*.svg; do xmllint --noout "$f"; done   # 다이어그램 XML 검증
for f in Constellate/Resources/Assets3D/*.usdz; do usdchecker --arkit "$f"; done   # 에셋 검증 (Blender 번들 pxr 또는 usd-core)
(cd ConstellateKit && CONSTELLATE_SNAPSHOT_DIR=../Blender/data swift test --filter SnapshotTests)   # 별자리 렌더 입력 갱신
```

## 파일 배치 (구현됨)

```
Constellate/
  App/        ConstellateApp.swift, AppModel.swift
  Views/      DashboardView, NavigatorView, InspectorView(+CodeInspectorWindow), CodeCardView, HostChatView,
              ThemePickerView, TimeDialView, ParticipantsView, TourBarView, VoiceButton,
              RelationLegendView (LayoutStylePicker · RelationModePicker · RelationSwatch · RelationToolbarControl)
  Spatial/    ConstellationSceneController, CodeNodeEntity, OrbEntity, BeaconEntity, AvatarEntity, EnvironmentEntity,
              EdgeRenderer(+FlowParticles), NodeStarFactory, FXTextures, MeshFactory, TextureFactory, AssetLoader
  Platform/   OrbitCameraRig, ConstellationViewport (iPad/Mac), ConstellationImmersiveView + HeadPoseProvider (visionOS),
              ScrollWheelMonitor (macOS)
  AI/         HostAI (LanguageModelSession · streamChat · 5 Tools · LocateAnswer/TourAnswer · 복구), HeuristicHost
  Voice/      SpeechListener, VoiceCommandRouter, HostVoice (TTS)
  Session/    ConstellateActivity, SessionCoordinator
  Support/    ColorBridge, SourceProvider, SyntaxHighlighter, PinsExporter
  Constellate.entitlements
  Resources/  Assets3D/*.usdz (8: 회의 에셋 7 + NodeStars), Textures/*.png (9: Sky_Dark · Sky_Tint · Floor_Grid · FX_* 6)
  Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png, icon_16…1024.png
ConstellateKit/Sources/ConstellateKit/{Graph(+Analysis, RelationKind, GraphInsights, RelationDigest),Ingest(+RelationClassifier),
              Layout(LayoutStyle, LayoutContext, RadialShell, Sphere, TreeRadial, Wall, Spiral),Geometry(EdgeScene, NodeStars, ConstellationSnapshot),
              Cluster,Search,Tour,Theme,Session,Sample}
ConstellateKit/Tests/ConstellateKitTests/{Theme,Extractor,Ingestor,Layout,LayoutStyle,Relation(+InspectorDigest),EdgeScene(+StarEncoder),Snapshot,
              Cluster,Search,Tour,SampleGraph,Codable,AppFacingAPI}Tests.swift + Fixtures/
Blender/scripts/{constellate_lib,build_assets,build_graph_assets,build_textures,render_assets,render_graph,render_icons,build_all}.py, make_icon_set.sh, README.md
Blender/data/orbitnotes_{celestial,shells,sphere,treeRadial,wall,spiral}.json
Blender/renders/{host_orb,cluster_orb,avatar_bust,beacon,review_pin,stage_ring,pointer_dart,theme_dark,theme_tinted_ocean,asset_sheet,
              layout_<style>×6,layout_celestial_eye,layout_gallery,node_stars,relation_legend}.png
Docs/  PRD-Tech-Constellate.md  PRD-Design-Constellate.md  TASKS-Constellate.md  VISION.md  diagrams/  images/
```
