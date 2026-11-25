#!/bin/bash
# Tajagi 빌드: swiftc → build/Tajagi.app → 코드 서명
#   서명 신원: 환경변수 SIGN_ID > local-sign-id 파일(깃에 안 올라감) > 애드혹("-")
#   본인 인증서로 서명하면 재빌드해도 '입력 모니터링' 권한이 유지된다. 애드혹이면 빌드할 때마다 다시 허용해야 한다.
#   UNIVERSAL=1 ./build.sh  → Apple Silicon + Intel 유니버설 바이너리
set -euo pipefail
cd "$(dirname "$0")"
SIGN_ID="${SIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
  if [[ -f local-sign-id ]]; then SIGN_ID="$(head -1 local-sign-id)"; else SIGN_ID="-"; fi
fi
APP="build/Tajagi.app"
mkdir -p build
EXTRA=()
# 일부 Command Line Tools에 남은 오래된 module.modulemap 충돌 우회
STALE=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [[ -f "$STALE" && -f "$(dirname "$STALE")/bridging.modulemap" ]]; then
  cat > build/vfs-overlay.yaml <<EOV
{ "version": 0, "case-sensitive": "false",
  "roots": [ { "type": "directory", "name": "$(dirname "$STALE")",
               "contents": [ { "type": "file", "name": "module.modulemap",
                               "external-contents": "$PWD/toolchain-fix/empty.modulemap" } ] } ] }
EOV
  EXTRA+=(-vfsoverlay build/vfs-overlay.yaml -Xcc -ivfsoverlay -Xcc build/vfs-overlay.yaml)
fi
compile() {   # $1 = arm64 | x86_64
  swiftc -O -target "$1-apple-macos13.0" -swift-version 5 ${EXTRA[@]+"${EXTRA[@]}"} \
    -framework AppKit -framework AVFoundation -framework Carbon -framework ServiceManagement -framework QuartzCore \
    Sources/*.swift -o "build/Tajagi-$1"
}
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  compile arm64; compile x86_64
  lipo -create build/Tajagi-arm64 build/Tajagi-x86_64 -output build/Tajagi-bin
else
  compile "$(uname -m)"; cp "build/Tajagi-$(uname -m)" build/Tajagi-bin
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Tajagi-bin "$APP/Contents/MacOS/Tajagi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign "$SIGN_ID" --identifier local.tajagi.Tajagi "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated || true
echo "Built: $PWD/$APP (sign=$SIGN_ID)"
