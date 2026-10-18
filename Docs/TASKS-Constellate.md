# Constellate — 태스크 문서 v1.1
PRD: `Docs/PRD-Tech-Constellate.md` (v1.0) · 디자인: `Docs/PRD-Design-Constellate.md` · 스펙: `Docs/VISION.md`
상태: **M0·M1·M2 완료, M3 구현 완료, M4·M5·M6 구현(실기기 미검증), M7 진행 (2026-10-19)** · 기준 환경: **Xcode 27 / visionOS 27 · iPadOS 27 · macOS 27**
작성자: 김민웅(콜슨)

범례: 🔴 P0 (핵심 체험) / 🟡 P1 (완성도) / ⚪ P2 (여유 시)
상태: `[x]` 완료 · `[~]` 진행 중/부분 · `[ ]` 미착수
각 태스크는 독립 빌드·검증 가능한 단위. 순서 = 의존성 순서.
회귀 확인 명령은 문서 끝 "회귀 확인" 절 참조. 현재 결과: `swift test` **54 테스트 / 9 스위트 통과**, `Scripts/build.sh all` **exit=0 ×3**.

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

## M4. 호스트 AI — 구현(스트리밍 제외), 실기기 미검증

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T4.1 | 🔴 | [x] | `HostAI` — 가용성 관찰, `LanguageModelSession` 생성·prewarm, 상태(idle/listening/thinking/speaking), 오브 연동 | `AI/HostAI.swift` | 가용/불가 두 경로 UI |
| T4.2 | 🔴 | [x] | Instructions 빌드 — 프로젝트 통계(`GraphStats`)·레이어 분포·선택/도킹 컨텍스트·언어, 절단 | `AI/HostAI.swift` | 컨텍스트 예산 내 |
| T4.3 | 🔴 | [x] | Tools 5종 — `LocateCode`, `ExplainNode`, `SummarizeCluster`, `ReviewNode`, `PlanTour` (`@Generable` 인자) | `AI/HostAI.swift` | 그래프 조회 결과 반환 |
| T4.4 | 🔴 | [x] | `@Generable` 응답 — `LocateAnswer{speech, nodeIDs}`, `TourAnswer{title, steps}` → 하이라이트/소환/투어 실행 | `AI/HostAI.swift` | 응답 → 씬 반영 |
| T4.5 | 🔴 | [x] | `HeuristicHost` 폴백 — 동일 인텐트를 CodeSearcher/heuristicSummary/TourBuilder로, 배지 | `AI/HeuristicHost.swift` | 시뮬레이터에서 5 인텐트 응답(`screenshot-ipad-summon.png`) |
| T4.6 | 🔴 | [x] | 컨텍스트 초과 복구 — 새 세션 재시도 → 폴백 | `AI/HostAI.swift` | 복구 경로 존재 |
| T4.7 | 🟡 | [ ] | **스트리밍 응답**(`streamResponse` → 말풍선 타이핑) — **미구현**, 현재 완성 응답 일괄 표시 | `Views/HostChatView.swift` | 부분 텍스트 표시 |
| T4.8 | 🟡 | [~] | 가드레일 거부 처리 — 오류 메시지 표시, 전용 문구/Idle 복귀 다듬기 필요 | `AI/HostAI.swift` | 거부 시 안내 + Idle |
| T4.9 | 🔴 | [ ] | **실기기 검증**(Vision Pro / M-시리즈 Mac, Apple Intelligence ON) — 5 도구 실호출 로그 | `Docs/images/ai-tools-log.png` | 성공 캡처 |

## M5. 음성 출두 — 구현, 실기기 미검증

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T5.1 | 🔴 | [x] | `SpeechListener` — `AVAudioEngine` 탭 → `SpeechAnalyzer`/`SpeechTranscriber`, 권한 안내, 스트림 | `Voice/SpeechListener.swift` | 시뮬레이터에서 가용성 분기 확인 |
| T5.2 | 🔴 | [x] | 웨이크워드 "Constellate"/"콘스텔" + 수동 Listening(`VoiceButton`) | `Voice/SpeechListener.swift`, `Views/VoiceButton.swift` | 감지 → Listening |
| T5.3 | 🔴 | [x] | `VoiceCommandRouter` — `parse(_:) -> VoiceIntent`(find/explain/summarize/review/tour/undock/follow/free) | `Voice/VoiceCommandRouter.swift` | 인텐트 라우팅 |
| T5.4 | 🔴 | [x] | `BeaconEntity` — `Beacon.usdz` + 테마 `beacon` 색, 등장/해제 | `Spatial/BeaconEntity.swift` | 비콘 표시·제거 |
| T5.5 | 🔴 | [x] | 소환(summon) — 복제 카드 → 사용자 앞, 가이드선, 해제 복귀, 하이라이트 링 | `Spatial/ConstellationSceneController.swift` | `screenshot-ipad-summon.png` |
| T5.6 | 🔴 | [x] | 텍스트 입력 폴백 — `HostChatView`가 동일 라우터 사용 | `Views/HostChatView.swift` | 시뮬레이터 전 인텐트 동작 |
| T5.7 | 🟡 | [ ] | TTS(`AVSpeechSynthesizer`) + Speaking 상태 연동 | `Voice/Speaker.swift` | 발화 중 에너지 0.75 |
| T5.8 | 🔴 | [ ] | **실기기 검증** — "콘스텔, @State를 쓰는 뷰 찾아줘" → 비콘 + 복제 카드 | `Docs/images/summon-device.png` | 캡처 |
| T5.9 | 🟡 | [ ] | `installTap` deprecation 경고 제거 — 새 `AVAudioInputNode` 비동기 API로 교체 | `Voice/SpeechListener.swift` | 경고 0 |

## M6. 회의 (GroupActivities) — 구현(시뮬레이션 멤버), 2기기 미검증

| ID | 우선 | 상태 | 태스크 | 산출물 | 완료 기준 |
|---|---|---|---|---|---|
| T6.1 | 🔴 | [x] | `ConstellateActivity` + `SessionCoordinator` — 세션 수명주기, `GroupSessionMessenger` JSON, 역할 결정, 솔로 모드, 시뮬레이션 멤버 | `Session/ConstellateActivity.swift`, `Session/SessionCoordinator.swift`, `Constellate.entitlements` | 로컬 시뮬레이션 멤버로 메시지 라운드트립(`screenshot-ipad-meeting.png`) |
| T6.2 | 🔴 | [~] | 핸드셰이크 — hello → roster/graphDigest/theme/timeDial/mode; 체크섬 불일치 시 그래프 구조 청크 전송은 **미구현** | `Session/SessionCoordinator.swift` | 4000 파일 전송 ≤ 5 s, 소스 본문 미포함 |
| T6.3 | 🔴 | [x] | `hostSpeech ask:` 규약 — member 질문 전달, host만 AI 수행, 답변 브로드캐스트 | `Session/SessionCoordinator.swift` | member 질문 → host 답변 |
| T6.4 | 🔴 | [x] | 역할 권한 — 테마/다이얼/모드/투어는 host만 | `Views/*`, `App/AppModel.swift` | member에서 제어 비활성 |
| T6.5 | 🔴 | [~] | follow-host — `followHost` 수신·상태 반영 ✔, iPad/mac 카메라 보간·visionOS 가이드선 다듬기 | `Session/SessionCoordinator.swift`, `Platform/OrbitCameraRig.swift` | 2기기 follow 확인 |
| T6.6 | 🔴 | [~] | 레이저 포인터 — `pointer` 메시지·`Pointer_Dart` 엔티티 ✔, **입력 제스처 바인딩 미구현** | `Spatial/ConstellationSceneController.swift` | 상대 기기에 다트 표시 |
| T6.7 | 🔴 | [~] | 리뷰 핀 — `pin`/`resolvePin` 수신·`ReviewPin` 표시·인스펙터 목록 ✔, 라인 핀 작성 UI·JSON 내보내기 | `Session/SessionCoordinator.swift`, `Views/InspectorView.swift` | 2기기 핀 동기화 + 내보내기 |
| T6.8 | 🔴 | [x] | 가이드 투어 — `tour`/`tourStep` 전파, host 전진/후진, 스텝 비콘 + 내레이션 | `Views/TourBarView.swift` | 시나리오 C 로컬 완주 |
| T6.9 | 🔴 | [x] | 아바타 — `Avatar_Bust.usdz` + 이름판, `Stage_Ring.usdz` 배치, `ParticipantsView` | `Spatial/AvatarEntity.swift`, `Views/ParticipantsView.swift` | 참가자 수만큼 흉상 |
| T6.10 | 🟡 | [ ] | 세션 종료 처리(host 이탈 안내), 재접속 | `Session/SessionCoordinator.swift` | 안내 표시 |
| T6.11 | 🔴 | [ ] | **2기기 실기 검증** — 시나리오 A/B/C, 라운드트립 측정 | `Docs/images/session-*.png` | ≤ 300 ms 기록 |
| T6.12 | 🟡 | [ ] | `Avatar_Bust` `Accent` 슬롯 런타임 재틴트(참가자 액센트) | `Spatial/AssetLoader.swift` | 참가자별 색 차이 |

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

---

## 알려진 갭 (2026-10-19, 솔직한 목록)

| 갭 | 영향 | 태스크 |
|---|---|---|
| 호스트 AI 응답 스트리밍 없음(완성 응답 일괄 표시) | 긴 답변에서 수 초 공백 | T4.7 |
| `Avatar_Bust.usdz` `Accent` 머티리얼 런타임 재틴트 없음 | 참가자 액센트 색이 흉상에 반영되지 않음(이름판만) | T6.12 |
| 레이저 포인터가 입력 제스처에 바인딩되지 않음 | 메시지·엔티티는 있으나 사용자가 쏠 수 없음 | T6.6 |
| 그래프 구조 청크 전송 미구현 | 같은 프로젝트가 없는 member는 별자리를 못 받음(샘플은 공유) | T6.2 |
| 씬 노드 캡 2500 / 전용 텍스처 400 | 대형 레포는 상위 가중치만 카드, 나머지는 폴더에 접힘/솔리드 | NFR-1.4(의도된 예산) |
| `AVAudioEngine.installTap` deprecation 경고 1건 | 빌드 경고 | T5.9 |
| 실기기 검증 미실시 — Vision Pro, 2기기 SharePlay, Apple Intelligence 실응답 | 시뮬레이터 폴백 경로만 확인됨 | T4.9 · T5.8 · T6.11 |
| macOS 스크린샷 없음(화면 기록 권한) | README 갤러리에 macOS 누락 | T7.3 |
| Blender MCP 미연결(CLI만 사용) | MCP 경로 산출물 동일성 미검증 | T7.6 |

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

```sh
cd ConstellateKit && swift test          # Kit 단위 테스트 — 현재 54 테스트 / 9 스위트 통과
Scripts/build.sh all                     # macOS · iPadOS 시뮬레이터 · visionOS 시뮬레이터 3 빌드, 각 exit=0
```

보조:

```sh
for f in Docs/diagrams/*.svg; do xmllint --noout "$f"; done   # 다이어그램 XML 검증
for f in Constellate/Resources/Assets3D/*.usdz; do usdchecker --arkit "$f"; done   # 에셋 검증 (Blender 번들 pxr 또는 usd-core)
```

## 파일 배치 (구현됨)

```
Constellate/
  App/        ConstellateApp.swift, AppModel.swift
  Views/      DashboardView, NavigatorView, InspectorView(+CodeInspectorWindow), CodeCardView, HostChatView,
              ThemePickerView, TimeDialView, ParticipantsView, TourBarView, VoiceButton
  Spatial/    ConstellationSceneController, CodeNodeEntity, OrbEntity, BeaconEntity, AvatarEntity, EnvironmentEntity,
              EdgeRenderer, MeshFactory, TextureFactory, AssetLoader
  Platform/   OrbitCameraRig, ConstellationViewport (iPad/Mac), ConstellationImmersiveView + HeadPoseProvider (visionOS),
              ScrollWheelMonitor (macOS)
  AI/         HostAI (LanguageModelSession · 5 Tools · LocateAnswer/TourAnswer · 복구), HeuristicHost
  Voice/      SpeechListener, VoiceCommandRouter
  Session/    ConstellateActivity, SessionCoordinator
  Support/    ColorBridge, SourceProvider, SyntaxHighlighter
  Constellate.entitlements
  Resources/  Assets3D/*.usdz (7), Textures/*.png (3)
  Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png, icon_16…1024.png
ConstellateKit/Sources/ConstellateKit/{Graph(+Analysis),Ingest,Layout,Cluster,Search,Tour,Theme,Session,Sample}
ConstellateKit/Tests/ConstellateKitTests/{Theme,Extractor,Ingestor,Layout,Cluster,Search,Tour,SampleGraph,Codable}Tests.swift + Fixtures/
Blender/scripts/{constellate_lib,build_assets,build_textures,render_assets,build_all}.py, make_icon_set.sh, README.md
Blender/renders/{host_orb,cluster_orb,avatar_bust,beacon,review_pin,stage_ring,pointer_dart,theme_dark,theme_tinted_ocean,asset_sheet}.png
Docs/  PRD-Tech-Constellate.md  PRD-Design-Constellate.md  TASKS-Constellate.md  VISION.md  diagrams/  images/
```
