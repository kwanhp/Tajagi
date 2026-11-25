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
- **한/영 전환:** 묵직한 키 '도각' + 종 두 음(한 = 올라감, 영 = 내려감)
- **여백 벨:** 65번째 글자에서 '띵'. 메뉴에서 켤 수 있다(기본 꺼짐)

## 화면 효과

- 화면 아래 둥근 키캡이 눌리며 깜박인다. 어떤 키를 눌렀는지는 표시하지 않는다
- 한/영 전환 때 키캡에 '한' / 'A'
- 클릭한 자리에 물결
- **테마 색상:** 앰버(기본)·민트·라벤더·벚꽃·바다·라임·다크 키캡. 메뉴의 **강조색 직접 고르기…**로 아무 색이나 고를 수도 있다

## 메뉴

메뉴바 ⌨ 아이콘에서 음량, 항목별 켜기/끄기, 테마, 소리 미리듣기, 로그인 시 자동 시작을 설정한다.
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

---

## English

**Tajagi** ("typewriter" in Korean) is a tiny macOS menu bar app that plays a deep, thocky mechanical-keyboard sound when you type and vintage typewriter sounds when you click or scroll. It also plays a small chime when you switch between Korean and English input.
All sounds are synthesized in code; there are no audio samples.
Install from [Releases](../../releases) (unsigned: use *Open Anyway* in Privacy & Security, or `xattr -dr com.apple.quarantine`), or build with `./build.sh`.
Keyboard sounds need **Input Monitoring** permission. Events are listen-only, and nothing is stored or sent anywhere.
MIT licensed.
