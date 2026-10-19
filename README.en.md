> 🇰🇷 **한국어 README**: [README.md](README.md) — this is the English version, kept for reference.
> The app itself is Korean-first (host AI replies, speech recognition, interface). English mode lives under Settings → Advanced → Language.

<p align="center">
  <img src="Docs/images/hero.png" width="1000" alt="Constellate — a code constellation in an immersive space with the host AI orb"/>
</p>

# Constellate

**Walk your codebase as a constellation — together, with an on-device AI host.**

Constellate turns a whole project into a multi-dimensional "code constellation" inside an immersive space (visionOS) or a RealityKit viewport (iPadOS / macOS). Every file and type is placed by rule — in the default *celestial* layout tree depth becomes distance, subtrees become azimuth sectors, the architecture layer becomes an elevation angle (UI overhead, data at the horizon, tests below), and recency becomes a fourth axis you scrub with a time dial. Relations are drawn by *meaning* — a screen presenting another, a view observing a model, a factory creating a type — each in its own colour, line style and 3-D lane, and every card wears a star whose shape, colour, size and glow say its role, layer, coupling and recency. The host's Apple Intelligence model lives in the space as a Siri-like orb: tap a cluster of code and the orb docks into it to answer with that code as context; pull it out and it follows you again. Say *"Constellate, find the views that use @State"* and the matching card flies to your hands while a beacon rises for everyone in the SharePlay session. No code ever leaves the device.

<p align="center">
  <img src="https://img.shields.io/badge/platforms-visionOS%2027%20%7C%20iPadOS%2027%20%7C%20macOS%2027-black?logo=apple" alt="platforms"/>
  <img src="https://img.shields.io/badge/Xcode-27-blue?logo=xcode" alt="Xcode 27"/>
  <img src="https://img.shields.io/badge/on--device%20AI-FoundationModels-7F7CFF" alt="FoundationModels"/>
  <img src="https://img.shields.io/badge/Kit%20tests-99%20passing-brightgreen" alt="99 tests"/>
  <img src="https://img.shields.io/badge/status-feature%20complete%20on%203%20platforms%20%C2%B7%20device%20validation%20pending-lightgrey" alt="status"/>
  <img src="https://img.shields.io/badge/license-Apache--2.0-green" alt="Apache-2.0"/>
</p>


## Videos

<table>
  <tr>
    <td align="center" width="50%"><a href="Docs/video/constellate-intro.mp4"><img src="Docs/video/constellate-intro.gif" alt="Constellate intro — highlight loop; click for the narrated MP4"/></a><br/><sub><b>Intro · 앱 소개</b> · 1:43 · <a href="Docs/video/constellate-intro.mp4">MP4</a></sub></td>
    <td align="center" width="50%"><a href="Docs/video/constellate-howto.mp4"><img src="Docs/video/constellate-howto.gif" alt="How to use Constellate — highlight loop; click for the narrated MP4"/></a><br/><sub><b>How to use · 사용법</b> · 2:04 · <a href="Docs/video/constellate-howto.mp4">MP4</a></sub></td>
  </tr>
</table>

Korean narration and subtitles, original score. The how-to film's Mac window is rebuilt from the SwiftUI source around the Orbit Notes sample (device recordings are still pending) — how both films were made: [Docs/video](Docs/video/README.md).

<!-- Inline players: edit this README on github.com, drag Docs/video/constellate-intro.mp4 and constellate-howto.mp4 onto
     the line below, and commit. GitHub uploads each file and inserts a https://github.com/user-attachments/assets/… line
     that plays right here. -->

---

## Features

- **Project ingest, on device** — point at a folder (≤ 4000 files); `ProjectIngestor` builds a `CodeGraph` (module → folder → file → type → member) with imports / inherits / references / calls edges. Swift symbols are extracted with a dependency-free scanner; `CodeGraph+Analysis` gives stats, hubs, entry points and busiest files.
- **Six constellation shapes** — `celestial` (default: spherical shells around your eyes — depth → distance, subtree → azimuth, layer → elevation), the v1 `shells` disc, and ports of CoulsonPortfolioWeb's `sphere` (Fibonacci dome with folder patches), `treeRadial`, `wall` (a curved wall in front of you) and `spiral`. Weighted sectors preserve the tree, card radius `0.08 + √lines/90` m, and a continuous **time dial** (−1…1) pushes recent code outward (spherically for the dome styles). Deterministic; same project, same sky. Switch from the toolbar, the visionOS dashboard or ⌃⌘1…6; the host's choice syncs over SharePlay.
- **Relations by meaning** — `RelationClassifier` (a port of the portfolio's `relations.js`) labels every reference: **presents** (sheet / NavigationLink / WindowGroup), **binds** (@State / @Environment / @Bindable — drawn from the source to the view), **composes**, **creates**, **conforms**, **extends**, **delegates**, **notifies**, **calls**, **imports**, **uses**. Each kind has a fixed colour, dashed or solid line, flow particles and arrowheads where data moves, and its own *lane* — a rotation of the arc around the chord — so different relations between the same two cards separate in 3-D. Off / focus / all (⌘L) and a legend that hides kinds; selecting a card dims everything it isn't related to. Relations are searchable too — *"views that present SettingsView"*, *"observed by NotesListView"*, *"SettingsView를 띄우는 뷰"* — in the navigator, by voice and through the host AI's `locateCode` tool.
- **Stars, coupling and cycles** — a glyph above each card encodes role (App, View, ViewModel, Model, Service, Test… from `inferRole`), layer colour, fan-in size and recency glow. `GraphInsights` lifts dependencies to files: fan-in / fan-out, instability, transitive impact and Tarjan cycles — select a file on a cycle and the whole loop lights up red. The inspector groups relations as "Presents / Observed by / Created by …", and the host AI receives the same digest as context.
- **Orbs for any unit of code** — group by folder / file / type / feature (`ClusterGranularity`); each cluster is a glass orb at its centroid that unfolds into code cards.
- **Host AI orb (dock / undock)** — the host's `FoundationModels` session is embodied as a Siri-like orb with five tools: `LocateCode`, `ExplainNode`, `SummarizeCluster`, `ReviewNode`, `PlanTour`, answering with `@Generable` `LocateAnswer` / `TourAnswer`; free-form chat streams token by token (`HostAI.streamChat`). Tap a cluster to dock the orb into it; drag it out to free it. `HeuristicHost` keeps every feature working when the model is unavailable.
- **Voice summon + spoken replies** — "Constellate" / "콘스텔" wake word via `SpeechAnalyzer`; `VoiceCommandRouter` picks the intent, the found card flies to you, a 3 m beacon rises at its origin, and the beacon is synchronized to all participants. `HostVoice` reads replies aloud (ko-KR / en-US auto, toggle persisted).
- **Meetings over SharePlay** — `GroupActivity` host + members, three modes (analysis / review / lecture), **laser pointer** (long-press + drag on iPad/Mac, pinch-hold on visionOS), **review pins** with Markdown export, **guided tours** with follow-host (the camera flies to each summoned/toured node on iPad/Mac; a glowing guide arrow on visionOS), stylized bust avatars retinted in each participant's accent on a stage ring. Members ask the host AI through the `hostSpeech("ask: …")` relay.
- **Rule-based themes** — `ConstellateTheme.dark` and `tinted(hue:)` presets (Ocean, Moss, Ember, Nebula). Environment stays dark and desaturated (chroma ≤ 0.16, L ≤ 0.30) and automatically avoids code hues; `validate()` enforces it in tests.
- **Privacy by construction** — parsing, AI inference and speech recognition all run on device. SharePlay carries node IDs, text and numbers only; source bodies are never transmitted.

## Platforms

| | visionOS 27 | iPadOS 27 | macOS 27 |
|---|---|---|---|
| Constellation | `ImmersiveSpace` (progressive), you stand at the origin | `RealityView` in a window + orbit camera | `RealityView` in a window + orbit camera (scroll-wheel zoom) |
| Host orb | Life-size in the space, 0.9 m in front of you, head-tracked | In the viewport + HUD | Same |
| Input | Gaze + pinch, hand drag, voice | Touch, Apple Pencil, voice | Mouse, keyboard, voice |
| Meeting | SharePlay with spatial Personas | SharePlay | SharePlay |
| Windows | Dashboard + Code Inspector | 3-column split | 3-column split + menu bar |

One multiplatform app target + the pure-Swift `ConstellateKit` package (Foundation + simd only, 99 tests).

## The constellation language

Rendered by Blender from the positions, arcs and legends ConstellateKit computes for the Orbit Notes sample (`Blender/data/*.json` → `render_graph.py`):

<p align="center"><img src="Blender/renders/layout_gallery.png" width="100%" alt="The six layout styles: celestial, shells, sphere, tree radial, wall, spiral"/></p>

<table>
  <tr>
    <td align="center"><img src="Blender/renders/layout_celestial_eye.png" width="480" alt="Celestial layout from the viewer's spot"/><br/><sub>Celestial · from where you stand</sub></td>
    <td align="center"><img src="Blender/renders/relation_legend.png" width="480" alt="Relation legend"/><br/><sub>Relations: colour = kind · dash = type system · arrow + particles = flow</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Blender/renders/node_stars.png" width="480" alt="Node star glyphs"/><br/><sub>Stars: shape = role · colour = layer · size = fan-in · glow = recency · ring = cycle</sub></td>
    <td align="center"><img src="Blender/renders/theme_dark.png" width="480" alt="Blender render — Dark theme"/><br/><sub>Meeting assets v2 under the new sky and astrolabe floor</sub></td>
  </tr>
</table>

## Screenshots

<table>
  <tr>
    <td align="center"><img src="Docs/images/screenshot-visionos-dashboard.png" width="480" alt="Vision Pro simulator — Dashboard window"/><br/><sub>Vision Pro simulator · Dashboard window</sub></td>
    <td align="center"><img src="Docs/images/screenshot-ipad-landscape.png" width="480" alt="iPad — constellation viewport, landscape"/><br/><sub>iPad · constellation viewport (landscape)</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Docs/images/screenshot-ipad.png" width="480" alt="iPad — constellation viewport, portrait"/><br/><sub>iPad · portrait</sub></td>
    <td align="center"><img src="Docs/images/screenshot-ipad-inspector.png" width="480" alt="iPad — code inspector"/><br/><sub>iPad · code inspector</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Docs/images/screenshot-ipad-summon.png" width="480" alt="iPad — voice summon with beacon"/><br/><sub>iPad · summon: beacon + card copy</sub></td>
    <td align="center"><img src="Docs/images/screenshot-ipad-meeting.png" width="480" alt="iPad — meeting with avatars"/><br/><sub>iPad · meeting mode, bust avatars</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Docs/images/screenshot-ipad-ocean.png" width="480" alt="iPad — Ocean tinted theme"/><br/><sub>iPad · Ocean tinted theme</sub></td>
    <td align="center"><img src="Blender/renders/theme_dark.png" width="480" alt="Blender render — Dark theme"/><br/><sub>Blender render · Dark theme scene</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src="Blender/renders/asset_sheet.png" width="320" alt="Asset sheet"/><br/><sub>Asset sheet (7 USDZ)</sub></td>
    <td align="center"><img src="Blender/renders/host_orb.png" width="320" alt="Host orb render"/><br/><sub>HostOrb.usdz</sub></td>
    <td align="center"><img src="Blender/renders/theme_tinted_ocean.png" width="320" alt="Ocean theme render"/><br/><sub>Blender render · Ocean</sub></td>
  </tr>
</table>

> **macOS screenshot pending** — the shell used for this session has no Screen Recording permission, so the macOS build (which compiles and runs) could not be captured yet. It will be added as `Docs/images/screenshot-macos.png`.

## Architecture

![Architecture](Docs/diagrams/architecture.svg)

- **Constellate app** — `App/` (`ConstellateApp`, `AppModel`), `Views/` (Dashboard, Navigator, Inspector + CodeInspectorWindow, CodeCard, HostChat, ThemePicker, TimeDial, Participants, TourBar, VoiceButton, RelationLegend), `Spatial/` (ConstellationSceneController, CodeNodeEntity, OrbEntity, BeaconEntity, AvatarEntity, EnvironmentEntity, EdgeRenderer + FlowParticles, NodeStarFactory, FXTextures, MeshFactory, TextureFactory, AssetLoader), `Platform/` (OrbitCameraRig, ConstellationViewport, ConstellationImmersiveView + HeadPoseProvider, ScrollWheelMonitor), `AI/` (HostAI, HeuristicHost), `Voice/` (SpeechListener, VoiceCommandRouter, HostVoice), `Session/` (ConstellateActivity, SessionCoordinator), `Support/` (ColorBridge, SourceProvider, SyntaxHighlighter, PinsExporter).
- **ConstellateKit** — `CodeGraph` (+Analysis), `RelationKind` / `CodeRole`, `GraphInsights`, `RelationDigest`, `ProjectIngestor` / `SwiftSymbolExtractor` / `RelationClassifier`, `ConstellationLayoutEngine` (six `LayoutStyle`s) / `ConstellationLayout`, `EdgeSceneBuilder` (relation tubes, flows, focus), `StarEncoder`, `ConstellationSnapshot`, `ClusterBuilder`, `CodeSearcher`, `TourBuilder`, `ConstellateTheme`, session models (`Participant`, `ReviewPin`, `LearningTour`, `ConstellateMessage`), `SampleGraph.orbitNotes()` (47 files, 15 folders, 50+ types).

More diagrams: [data flow](Docs/diagrams/dataflow.svg) · [4-D layout](Docs/diagrams/layout-4d.svg) · [session topology](Docs/diagrams/session-topology.svg) · [host orb states](Docs/diagrams/orb-states.svg).

## How it works

![Data flow](Docs/diagrams/dataflow.svg)

1. **Ingest** — `ProjectIngestor.ingest(rootURL:)` walks the folder on a background task, extracts Swift symbols, infers architecture layers and roles, classifies every reference into a `RelationKind` and records modification dates → `CodeGraph`; `GraphInsights` then derives file dependencies, cycles and coupling.
2. **Layout** — `ConstellationLayoutEngine(style:).layout(_:)` assigns every spatial node `position4 = (x, y, z, w)` by the chosen style (celestial: distance from depth, azimuth from subtree weight, elevation from layer; `w` from recency). `ConstellationLayout.position3(for:timeDial:)` projects to 3-D continuously; the scene never re-lays out when you turn the dial.
3. **Relations** — `EdgeSceneBuilder` turns relation edges into merged tube meshes per kind × emphasis (Bézier arcs in per-kind lanes, dashes, arrowheads) plus particle paths, off the main actor; the app shades them with the Blender `FX_EdgeRamp` so each edge brightens toward its target.
4. **Orbs** — `ClusterBuilder` groups nodes at the chosen granularity; each `CodeCluster` becomes an orb at `layout.centroid(of:)`. The scene shows up to 2500 node entities and 400 bespoke code textures (the rest are solid layer-coloured cards).
5. **Host AI** — on the host device, `HostAI` wraps a `LanguageModelSession` with five tools grounded in the graph (`CodeSearcher`, `TourBuilder`, `GraphStats`). Docking a cluster puts its code into the prompt context; context-window overflow starts a fresh session once, then falls back. If the model is unavailable, `HeuristicHost` answers from the same Kit calls.
6. **Voice summon** — `SpeechListener` transcribes with `SpeechAnalyzer`, the wake word gates listening, `VoiceCommandRouter` picks the intent, and the result raises a `BeaconEntity` plus a summoned card copy.
7. **SharePlay** — `SessionCoordinator` broadcasts `ConstellateMessage` values as JSON (highlight, summon, orbDock, hostSpeech, pointer, pin, theme, timeDial, mode, tour, followHost, layoutStyle, relationMode). Members ask the host AI through `hostSpeech(text: "ask: …")`.

## Getting started

Requirements: **Xcode 27**, macOS 27. Apple Intelligence and `SpeechAnalyzer` models are only available on devices (not in simulators) — the app falls back to heuristic answers and text input there.

```sh
git clone https://github.com/kimminung/Constellate.git
cd Constellate
open Constellate.xcodeproj          # pick the Constellate scheme and a visionOS / iPad / Mac destination

Scripts/build.sh all                # build macOS + iPadOS simulator + visionOS simulator (exit=0 ×3)
cd ConstellateKit && swift test     # 99 tests — AppFacingAPITests uses a plain `import`, so it fails
                                   # if the Kit stops exposing an API the app calls (no Xcode needed)
```

The app opens with the built-in **Orbit Notes** sample project (47 files), so you can explore a constellation before granting folder access.

## Blender asset pipeline

All 3-D assets, effect sprites, textures, renders and the app icon are produced headlessly by Blender 5.2 from `Blender/scripts/` (no `.blend` files are kept — see `Blender/scripts/README.md`):

```sh
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
cd Blender/scripts
$BLENDER --background --python build_all.py        # assets → stars + FX → textures → renders → constellation renders → icons
./make_icon_set.sh                                 # mac_16…512 from mac_1024 + Docs/images/icon-256.png
$BLENDER --background --python build_graph_assets.py              # NodeStars.usdz + FX_*.png only
$BLENDER --background --python render_graph.py -- --quick         # layout gallery + legends, fast preview
$BLENDER --background --python build_textures.py -- --fallback    # numpy sky in seconds instead of Cycles
```

**v2 "observatory instruments"** — the meeting assets were redesigned as precise astronomical instruments (an armillary host orb, a geodesic cluster orb, a visored bust with headset, a beacon with tractor rings and a floor medallion, a jewel review pin, an astrolabe stage ring, a crystal pointer), every one under its triangle budget and passing the ARKit USD rules. The sky now has a Milky Way, dust rifts, two nebula layers and four star magnitudes (still OKLab L ≤ 0.29, chroma ≤ 0.06); the floor is an astrolabe whose rings sit exactly under the layout's depth shells.

| Script | Output |
|---|---|
| `constellate_lib.py` | shared palette / materials / USDZ export + verification / PNG writer |
| `build_assets.py` | `Constellate/Resources/Assets3D/{HostOrb,ClusterOrb,Avatar_Bust,Beacon,ReviewPin,Stage_Ring,Pointer_Dart}.usdz` |
| `build_graph_assets.py` | `Assets3D/NodeStars.usdz` (15 star glyphs) + `Textures/FX_{Glow,Spark,Ring,Beam,EdgeRamp,CardGlow}.png` |
| `build_textures.py` (`--fallback`, `--derived-only`, `--sky-only`, `--floor-only`) | `Resources/Textures/{Sky_Dark,Sky_Tint,Floor_Grid}.png` |
| `render_assets.py` | `Blender/renders/*.png` (asset + theme renders) |
| `render_graph.py` | `Blender/renders/{layout_*,layout_gallery,node_stars,relation_legend}.png` from `Blender/data/*.json` |
| `render_icons.py` | platform app icons: iOS light/dark/tinted, macOS rounded tile, visionOS Front/Middle/Back layers, `Blender/renders/icon_sheet.png` |
| `build_all.py` (`--skip-*`, `--skip-graph`, `--skip-graph-renders`, `--skip-icons`, `--fallback-sky`) | everything above |

Material slots are fixed (`Core`, `Band0…Band3`, `Shell`, `Accent`, `Glass`, `Base`) so the app swaps them for theme-driven materials at runtime; every USDZ passes the ARKit USD rules. Blender 5.2 ignores the Principled Alpha socket, so the exporter post-processes `inputs:opacity` with `pxr`. The FX sprites are emission planes whose strength is a small formula (`constellate_lib.Field`) rendered by Cycles to linear EXR and stored as white + alpha, so one texture is tinted with any colour. `Sky_Dark.png` is a Cycles render (4096×2048, 12 samples, denoise off to keep 1–2 px stars); presentation renders use AgX + bloom. The Blender MCP server was not connected in this session, so the CLI path was used — the same scripts run unchanged under MCP `execute_blender_code`. If assets are missing the app uses procedural fallbacks.

## App icons

All platform icons are rendered in Blender from one scene (same camera, so the visionOS layers align): the host orb as hero, a small constellation of code cards with cyan/amber/pink glints, two cluster orbs and sharp stars.

<img src="Blender/renders/icon_sheet.png" alt="App icons: iOS light / dark / tinted, macOS tile, visionOS layers" width="100%">

| Platform | Files | Notes |
|---|---|---|
| iOS / iPadOS | `AppIcon-1024.png`, `-dark.png`, `-tinted.png` | three appearances (`luminosity` dark / tinted) in `AppIcon.appiconset` |
| macOS | `mac_1024.png` → `mac_16…512.png` | rounded tile (r 22.4 %), 10 % margin, glass rim light |
| visionOS | `AppIcon.solidimagestack/{Back,Middle,Front}` | Back = space + stars, Middle = cards + cluster orbs, Front = host orb; parallax on hover |

## Roadmap

From `Docs/TASKS-Constellate.md` (2026-10-19, after PR #1 and the second app round):

- [x] **M0** — project skeleton, `ConstellateKit` API contract, theme rules + tests, VISION / PRDs / diagrams, Blender pipeline, first build on all three platforms
- [x] **M1** — Kit: symbol extractor, ingestor, radial shell layout, clusters (4 granularities), EN/KO structural search, tour builder, Orbit Notes sample, graph analysis — 54 tests pass
- [x] **M2** — constellation scene: node entities + textures, edges, environment, orbit camera (iPad/Mac), immersive space (visionOS), time dial, themes
- [x] **M3** — cluster orbs, host orb presence, dock / undock, navigator, inspector + code window
- [ ] **M4** — host AI: session, five tools, `@Generable` answers, fallback, context recovery, **streaming chat replies** *(implemented; explain/review/summarize tool replies still arrive whole; real-device Apple Intelligence validation pending)*
- [ ] **M5** — voice: `SpeechAnalyzer` listener, wake words, intent router, beacons, summon, **TTS (`HostVoice`)** *(implemented; real-device validation pending; one `installTap` deprecation warning)*
- [ ] **M6** — meetings: GroupActivities, roles, `ask:` relay, **follow-host camera / guide arrow**, **laser pointer gesture**, **pins with resolve/delete + Markdown export**, tours, **accent-retinted avatars** *(implemented with simulated members; pointer release is not broadcast so a remote dart stays at its last spot; graph-chunk sync missing; 2-device validation pending)*
- [ ] **M7** — performance budget (90 fps visionOS, 1500 edges, 2500 nodes / 400 textures), accessibility, macOS screenshot, device validation
- [ ] **M8** — constellation language v2: relation kinds + classifier, six layout styles, node stars, dependency insights, inspector digests, Blender v2 assets / FX / sky / floor, constellation renders *(Kit: done, 99 tests; app builds and runs on macOS with zero warnings — iPadOS / visionOS simulator builds pending)*

## Credits

Constellate consolidates three earlier experiments by the same author:

- **Immersive Code Calligram IDE** — glyph atlas single-mesh text, iridescent ShaderGraph, procedural sky dome, debounced async execution.
- **CoulsonAndJarvis** — the Siri-like orb entity and presence state machine, FoundationModels session wrapper with fallback, SpeechAnalyzer wake-word pipeline, summon-to-front behaviour.
- **CodeFlow3D** — graph / anchor / edge model, continuous tilt projection (now the time dial), single-canvas edge rendering with particles, layer-band colours, review pins.

Author: 김민웅 (Minung Kim, "Coulson") — [github.com/kimminung/Constellate](https://github.com/kimminung/Constellate)

## License

Apache License 2.0 — see [LICENSE](LICENSE). Copyright 2026 Minung Kim (Coulson).
