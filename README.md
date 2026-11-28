# Tajagi (타자기)

키보드를 치면 묵직한 기계식 키보드 소리, 마우스·트랙패드를 클릭하면 옛날 타자기 소리가 나는 macOS 메뉴바 앱.
한/영을 바꾸면 작은 종소리가 난다.

녹음 파일 없이 모든 소리를 코드로 합성한다(`Sources/SoundBank.swift`, `Sources/Synth.swift`). 그래서 앱이 200 KB도 안 된다.

## 소리

- **키보드:** 묵직한 기계식 키보드(PBT 키캡 + 흡음 케이스 느낌)
  - 누를 때 '도각', 뗄 때 '톡'
  - 스페이스·엔터·백스페이스·시프트는 스테빌라이저 키라 더 낮고 깊다
  - 꾹 누르고 있을 때(자동 반복)는 진짜 키보드처럼 조용하다
- **클릭:** 타자기 활자대 '착', 뗄 때 캐리지 '틱', 오른쪽 클릭은 타자기 스페이스바 '덜컥'
- **스크롤:** 타자기 플래튼 노브 래칫 틱
- **드래그:** 캐리지가 랙을 타고 넘어가는 낮은 '틱'. 끌고 간 거리만큼 난다(빨리 끌면 조금 더 또렷하게)
- **한/영 전환:** 묵직한 키 '도각' + 종 두 음(한 = 올라감, 영 = 내려감)
- **여백 벨:** 65번째 글자에서 '띵'. 메뉴에서 켤 수 있다(기본 꺼짐)

## 화면 효과

- 화면 아래 둥근 키캡이 눌리며 깜박인다. 어떤 키를 눌렀는지는 표시하지 않는다
- 한/영 전환 때 키캡에 '한' / 'A'
- 클릭한 자리에 물결
- **테마 색상:** 앰버(기본)·민트·라벤더·벚꽃·바다·라임·다크 키캡. 메뉴의 **강조색 직접 고르기…**로 아무 색이나 고를 수도 있다

## 메뉴

메뉴바 ⌨ 아이콘에서 음량, 항목별 켜기/끄기, 테마, 소리 미리듣기, 로그인 시 자동 시작을 설정한다.

**부스트**(끔·약·중·강·최강)는 시스템 볼륨을 건드리지 않고 타자 소리만 키운다. 노래를 들으면서 쓸 때 노래는 그대로 두고 타자 소리만 올리고 싶을 때 쓴다. 컴프레서·소프트 포화·피크 리미터를 거쳐서 클리핑 없이 커진다(최강에서 키 소리 약 +11 dB).
**⌃⌥M**으로 소리를 켜고 끈다.

## 설치

macOS 13 이상. Apple Silicon과 Intel 모두 된다.

### 방법 1: 받아서 바로 쓰기

1. [Releases](../../releases)에서 `Tajagi-x.y.z-macOS.zip`을 받아 풀고, `Tajagi.app`을 `응용 프로그램` 폴더로 옮긴다.
2. Apple 개발자 인증서로 서명된 앱이 아니라서 처음엔 macOS가 막는다. 둘 중 하나로 연다.
   - 한 번 열어 본 뒤 **시스템 설정 › 개인정보 보호 및 보안** 아래쪽의 **그래도 열기**
   - 또는 터미널에서
     ```bash
     xattr -dr com.apple.quarantine /Applications/Tajagi.app
     ```
3. 키보드 소리를 내려면 **시스템 설정 › 개인정보 보호 및 보안 › 입력 모니터링**에서 Tajagi를 켠다. 켠 다음 메뉴의 **다시 실행**을 누른다.
   클릭·스크롤 소리는 권한 없이도 난다.

### 방법 2: 소스에서 빌드

Xcode 또는 Command Line Tools(`xcode-select --install`)가 있으면 된다.

```bash
git clone https://github.com/kwanhp/Tajagi.git
cd Tajagi
./build.sh      # build/Tajagi.app 생성
./run.sh        # 실행(이미 켜져 있으면 껐다 켠다)
```

- `UNIVERSAL=1 ./build.sh`: Apple Silicon + Intel 유니버설 빌드
- 기본은 애드혹 서명이라, 다시 빌드하면 입력 모니터링 권한을 다시 켜야 한다.
  키체인에 코드 서명 인증서가 있으면 그 이름을 `local-sign-id` 파일에 한 줄로 적어 둔다(또는 `SIGN_ID=...`).
  그러면 재빌드해도 권한이 유지된다.
- `build/Tajagi.app/Contents/MacOS/Tajagi --render <폴더>`: 모든 소리를 WAV로 저장한다(소리 다듬을 때).

## 개인정보

- 키보드·마우스 이벤트는 **듣기만(listen-only)** 하고 바꾸거나 막지 않는다.
- 키코드는 소리 종류와 좌우 위치를 고르는 데만 쓰고, 저장하거나 어디로 보내지 않는다. 네트워크 코드가 없다.
- 암호 입력란(보안 입력)에서는 macOS가 키 이벤트를 아예 넘겨주지 않는다.

## 소리 손보기

- 키보드: `Sources/SoundBank.swift`의 `press` / `release`, `Sources/Synth.swift`의 `Machine.keyboard` / `Machine.longKey`
- 타자기: 같은 파일의 `typebar`, `escapement`, `Machine.typebar` 등
- 색: `Sources/Theme.swift`

## 부록 A: Claude로 만들었다

이 앱의 코드, 소리 설계, README, CHANGELOG는 전부 Anthropic의 Claude가 썼다. 사람은 귀로 듣고 "이건 태고의 달인 같다", "더 묵직하게" 같은 피드백만 줬다.

| 항목 | 내용 |
|---|---|
| 모델 | **Claude Opus 5.5** (`claude-opus-5-5`) |
| 도구 | **Claude Code**: Claude 데스크톱 앱의 Code 탭 |
| 추론 강도(effort) | high |
| 권한 모드 | **bypass permissions**: 파일 수정과 터미널 명령을 매번 묻지 않고 바로 실행 |
| 사람이 직접 한 것 | 소리 듣고 피드백, macOS 입력 모니터링 권한 허용, 공개 결정 |
| 걸린 시간 | 첫 요청부터 "딱 좋아"(0.0.3)까지 약 27분. 테마와 공개까지 합쳐 반나절 |

작업 흐름:
1. Claude가 소리를 코드로 합성한다.
2. `--render`로 WAV를 뽑아 스펙트럼과 음정감 지표로 스스로 점검한다.
3. 빌드하고 다시 실행한다.
4. 사람이 실제로 쳐 보고 한 줄 피드백을 준다.
5. 반복한다.

버전별로 어떤 피드백이 무엇을 바꿨는지는 [CHANGELOG.md](CHANGELOG.md)에 있다.

## 부록 B: 변경 기록

[CHANGELOG.md](CHANGELOG.md) 참고. 요약:
- **0.1.3:** 부스트 강·최강에서 한/영 종소리·여백 벨이 깨지던 문제 수정
- **0.1.2:** 부스트(시스템 볼륨 그대로 타자 소리만 키우기)
- **0.1.1:** 드래그 소리, 출력 장치 전환 후 무음 버그 수정
- **0.1.0:** 테마 색상, 유니버설 빌드, 첫 공개
- **0.0.3:** 키보드는 묵직한 기계식, 클릭은 타자기로 역할 교체
- **0.0.2:** 북소리 같던 합성을 기계 몸통 모델로 갈아엎음
- **0.0.1:** 첫 빌드

---

## English

**Tajagi** ("typewriter" in Korean) is a tiny macOS menu bar app that plays a deep, thocky mechanical-keyboard sound when you type and vintage typewriter sounds when you click, scroll or drag. It also plays a small chime when you switch between Korean and English input.
All sounds are synthesized in code; there are no audio samples.
Install from [Releases](../../releases) (unsigned: use *Open Anyway* in Privacy & Security, or `xattr -dr com.apple.quarantine`), or build with `./build.sh`.
Keyboard sounds need **Input Monitoring** permission. Events are listen-only, and nothing is stored or sent anywhere.
MIT licensed.

**Made with Claude.** All code, sound design and docs were written by Claude Opus 5.5 (`claude-opus-5-5`). It ran in Claude Code in the Claude desktop app, at effort high, in bypass-permissions mode. The human only listened and gave feedback. See [CHANGELOG.md](CHANGELOG.md) for how each round of feedback changed the sound.
