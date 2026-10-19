# Constellate 소개 · 사용법 영상

| 파일 | 내용 |
|---|---|
| `constellate-intro.mp4` | 앱 소개 영상. 1분 43초, 1920×1080 30fps, H.264 + AAC, 9.4 MB. 한국어 내레이션·자막과 배경 음악이 들어 있습니다 |
| `constellate-intro.gif` | 소개 영상 하이라이트 22.7초, 720px 10fps, 8.2 MB. 소리는 없고 자막은 그대로 보입니다 |
| `constellate-howto.mp4` | 사용법 영상. 2분 4초, 1920×1080 30fps, H.264 + AAC, 9.6 MB. 11개 장으로 나뉘고 내레이션·자막·배경 음악·UI 효과음이 들어 있습니다 |
| `constellate-howto.gif` | 사용법 영상 하이라이트 23초, 720px 10fps, 5.8 MB |

네 파일 모두 GitHub 첨부 한도(10 MB)보다 작습니다.

## README에서 바로 재생하기

GitHub README는 저장소 안의 `.mp4`를 재생기로 보여 주지 않고, GitHub에 업로드한 동영상(`https://github.com/user-attachments/assets/…`)만 재생기로 보여 줍니다. 그래서 README에는 자동 재생되는 GIF를 넣고, GIF를 누르면 저장소의 MP4가 열리도록 했습니다. README 안에서 바로 재생되게 하려면 아래처럼 한 번만 올리면 됩니다.

1. GitHub에서 `README.md`를 열고 연필(Edit) 버튼을 누릅니다.
2. `Docs/video/constellate-intro.mp4`를 편집기 안의 원하는 자리(예: `## Videos` 바로 아래)로 끌어다 놓습니다. 업로드가 끝나면 `https://github.com/user-attachments/assets/…` 한 줄이 생깁니다.
3. `constellate-howto.mp4`도 같은 방법으로 올리고 커밋합니다. 그 줄이 README에서 재생기로 바뀝니다.

## 화면에 나오는 내용의 출처

- **3-D 장면**: 두 영상의 별자리는 ConstellateKit이 계산한 Orbit Notes 샘플 스냅샷(`Blender/data/orbitnotes_*.json`, 노드 125개·관계 257개·배치 6종)을 three.js로 다시 그린 것입니다. 관계선 곡선은 `EdgeSceneBuilder.arc`를 그대로 옮겨 여섯 배치 모두에서 원본 좌표와 비교해 확인했고(오차 약 10⁻⁶ m), 카드·별·오브·비콘·아바타·핀은 앱의 Blender 텍스처(`Constellate/Resources/Textures`)와 USDZ 에셋(`Resources/Assets3D`, GLB로 변환)을 씁니다. 관계 색·차선·고도, 레이어 색, 테마 하늘 색은 `RelationKind.style`, `ConstellateTheme`의 값입니다.
- **사용법 영상의 Mac 창은 실제 화면 녹화가 아닙니다.** `SplitDashboard`(`DashboardView.swift`)와 `NavigatorView`, `InspectorView`, `RelationLegendView`, `TimeDialView`, `TourBarView`의 SwiftUI 코드를 보고 HTML로 다시 만든 화면입니다. 툴바 순서, 메뉴 항목과 단축키(⌘O, ⌃⌘1–6, ⌘L, ⇧⌘V, ⌥⌘0), HUD 문구, 토스트("Relations · 관계: …", "Mina joined · 참가"), 인스펙터 구성(Coupling · 결합도, Relations · 관계 묶음 이름, Review pins · 핀, Export pins)은 코드에 있는 문자열을 그대로 썼습니다. 창 안의 별자리는 위와 같은 데이터로 그린 실제 배치입니다.
- **샘플 수치**: 47개 파일·3,891줄, `NotesListView.swift` 184줄·2026년 9월 30일 수정, `NoteDetailView` L7–131, 투어 1·2단계("Entry point: OrbitNotesApp", "Features/ … 14 files and 1489 lines")는 `SampleGraph.swift`와 `TourBuilder`의 값입니다. 결합도 숫자는 `GraphInsights`와 같은 규칙으로 계산했습니다.
- **호스트 답변 문장**은 예시입니다. 실제 앱에서는 기기 안의 Apple Intelligence 모델이 답하므로 문장이 매번 조금씩 다릅니다. 음성 명령 "콘스텔, 최근 코드 보여 줘"가 타임 다이얼을 최근 쪽으로 미는 동작은 `VoiceCommandRouter`의 규칙입니다.
- **visionOS 장면**은 `Docs/images/screenshot-visionos-dashboard.png` 실제 스크린샷에 시선·핀치 표시만 얹었고, 이어지는 몰입 공간은 같은 별자리를 눈높이에서 렌더한 것입니다. FaceTime·SharePlay 패널은 시스템 화면을 단순하게 그린 그림이고, 참가자 이름(Mina, Jae, Sora)은 `SessionCoordinator`의 데모 이름입니다.
- **기기 검증 전**: README 배지대로 실제 기기 검증은 아직 남아 있어, 영상의 UI는 코드 기준 재현입니다. 실제 화면 녹화가 생기면 같은 내레이션 타임라인에 맞춰 바꿀 수 있습니다.

## 만든 방법

- **내레이션**: [Supertonic 3](https://github.com/supertone-inc/supertonic) 한국어 음성(sherpa-onnx, 화자 4, 속도 1.04)입니다. 줄마다 5~8개 테이크를 만들고 SenseVoice 음성 인식으로 발음을 검사해 가장 또렷한 테이크를 골랐습니다. 음악을 깐 최종 믹스에서도 줄별로 다시 인식시켜 확인했습니다(사용법 영상 평균 글자 오류율 약 3%).
- **음악**: 직접 작곡했습니다. 소개 영상은 "Observatory"(D 리디안, 80 BPM, 패드·하프·첼레스타·글로켄슈필·현악·피아노), 사용법 영상은 같은 음색으로 조금 가볍게 쓴 "Field Notes"(84 BPM, 하프 오스티나토와 부드러운 박동)입니다. mido로 MIDI를 쓰고 FluidSynth와 MuseScore General 사운드폰트로 렌더링한 뒤 pedalboard로 공간감을 더했습니다. 카드가 나타나는 순간, 배치 전환, 장 시작 같은 화면 이벤트에 첼레스타와 글로켄슈필이 맞춰 울립니다.
- **효과음**: 마우스 클릭, 키 입력, 타이핑, 메뉴, 토스트, 화면 전환, 비콘, 도킹, 마이크, 참가자 입장, 레이저 포인터 소리를 numpy로 합성했습니다.
- **믹스**: 내레이션이 나오면 음악이 자동으로 작아지고(−9 dB, 1.2 kHz 이상은 −4 dB 더), 전체 −16 LUFS·true peak −1.2 dBTP 이하로 맞췄습니다.
- **화면**: 모든 프레임은 시간 t의 순수 함수 `window.seek(t)`입니다. 헤드리스 Chromium(SwiftShader WebGL)에서 프레임마다 캡처해 ffmpeg로 마스터를 만들고, 2패스 H.264로 10 MB 아래에 맞췄습니다. 글꼴은 Pretendard와 DejaVu Sans Mono, 아이콘은 SF Symbols 대신 비슷한 모양의 Lucide입니다.

## 구성

```
src/
├── web/
│   ├── intro.html · js/intro.js        소개 영상 장면
│   ├── usage.html · js/usage.js · css/usage.css   사용법 영상 (Mac 창 재현 + 장면)
│   ├── js/engine.js · cards.js · theme.js   공용 3-D 렌더러 (ConstellateKit 규칙 포팅)
│   ├── data/graph.js                   샘플 그래프 (tools/prep_data.py가 생성)
│   ├── data/tl_intro.js · tl_usage.js  내레이션 타임라인 (audio/build_narration.py가 생성)
│   ├── data/icons.js                   아이콘 묶음 (tools/icons.py가 생성)
│   └── assets/img/hero_*.png           Docs/images/hero.png에서 잘라 낸 로고
├── tools/
│   ├── prep_assets.py                  저장소의 텍스처·USDZ·이미지·스냅샷 → web/assets, web/data
│   ├── convert_usdz.py · prep_data.py · icons.py
│   ├── render.py · stills.py · export_events.py   프레임 캡처, 정지 화면, 음악용 이벤트
│   └── encode.sh · make_gif.py         MP4 (2패스, 10 MB 미만), GIF
└── audio/
    ├── script_intro.json · script_usage.json · timing_*.json   대본과 줄 간격
    ├── tts.py · takes.py · asr.py · build_narration.py           내레이션
    ├── music_intro.py · music_usage.py · mix.py                  음악·효과음·믹스
    └── get_models.sh                    Supertonic 3 · SenseVoice 모델 내려받기
```

## 다시 만들기

```bash
cd Docs/video/src
(cd web && npm install)                         # three, pretendard, lucide-static
pip install playwright usd-core trimesh pillow numpy scipy soundfile pyloudnorm pedalboard mido sherpa-onnx
python3 -m playwright install chromium
python3 tools/prep_assets.py                    # 저장소의 텍스처·에셋·스냅샷 → web/assets, web/data
(cd web && python3 -m http.server 8765 --bind 127.0.0.1 &)

# 1) 오디오 (선택: 대본을 바꿀 때만)
audio/get_models.sh
brew install fluid-synth                        # + MuseScore_General.sf3 (SOUNDFONT 환경 변수로 경로 지정)
python3 audio/takes.py script_usage.json 5      # 줄마다 5테이크 → ASR 검사
python3 audio/build_narration.py script_usage.json timing_usage.json   # → audio/build/usage, web/data/tl_usage.js
python3 tools/export_events.py usage.html audio/build/usage/events.json
python3 audio/music_usage.py usage && python3 audio/mix.py usage       # → audio/build/usage/mix.wav

# 2) 영상과 GIF
python3 tools/render.py usage.html ../usage_master.mkv 30
tools/encode.sh ../usage_master.mkv audio/build/usage/mix.wav ../constellate-howto.mp4 515 "Constellate — 사용법"
python3 tools/make_gif.py ../usage_master.mkv ../constellate-howto.gif 720 10 27.5-34.3 46.0-51.4 64.0-70.2 110.9-115.5
```

소개 영상은 `intro` / `script_intro.json` / `music_intro.py intro`로 같은 순서를 따르고, 인코딩 비트레이트는 620 kbps입니다(GIF 구간: `10.2-14.8 41.6-45.6 55.6-62.6 74.3-77.8 82.0-85.6`).

화면만 고칠 때는 1단계를 건너뛰고 기존 영상의 소리를 그대로 쓰면 됩니다.

```bash
ffmpeg -i ../constellate-howto.mp4 -vn -c copy audio/build/usage_mix.m4a
tools/encode.sh ../usage_master.mkv audio/build/usage_mix.m4a ../constellate-howto.mp4 515
```

`python3 tools/stills.py usage.html ../stills 30 50.5`처럼 원하는 시점의 정지 화면만 뽑아 볼 수 있습니다.
