#!/bin/zsh
# 배포용 DMG(build/Jupjup-<버전>.dmg): Jupjup.app · 응용 프로그램 바로가기 · 처음 여는 방법(한/영) · 라이선스.
# 리포트 키는 report.env에서(있으면). "Jupjup Dev" 인증서가 있으면 그걸로, 없으면 애드혹으로 서명한다.
# 아직 Apple 공증 전이라 받는 쪽 Mac에서 처음 한 번은 "그래도 열기"가 필요하다(안내 글에 적음).
# 배치 화살표 배경은 Finder 자동화 권한이 필요해 하지 않는다 — Finder 기본 배치 그대로.
set -e
cd "$(dirname "$0")/.."
BUILD="${TMPDIR:-/tmp}/jupjup-build"   # iCloud 폴더 밖에서 빌드 (codesign xattr 문제)
[ -f report.env ] && source report.env
xcodegen generate --quiet
xcodebuild -project Jupjup.xcodeproj -scheme Jupjup -configuration Release -derivedDataPath "$BUILD" \
  -destination 'generic/platform=macOS' \
  JJ_SENTRY_DSN="${JJ_SENTRY_DSN:-}" JJ_TELEMETRY_APP_ID="${JJ_TELEMETRY_APP_ID:-}" JJ_CONTACT="$(head -1 CONTACT)" -quiet build
APP="$BUILD/Build/Products/Release/Jupjup.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p build
DMG="build/Jupjup-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Jupjup Dev"'; then
  codesign --force --deep --sign "Jupjup Dev" --preserve-metadata=entitlements,flags "$STAGE/Jupjup.app"
fi
codesign --verify --deep --strict "$STAGE/Jupjup.app"
ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"
cat > "$STAGE/처음 여는 방법.txt" <<'TXT'
줍줍 설치와 처음 열기

1. Jupjup.app을 옆의 Applications(응용 프로그램) 폴더로 끌어 넣습니다.

2. 응용 프로그램 폴더에서 Jupjup을 엽니다.
   줍줍은 아직 Apple 공증을 받지 않아, 처음 열 때 열 수 없다는 창이 뜹니다.
   그 창은 "완료"로 닫고(휴지통으로 옮기지 마세요),
   시스템 설정 › 개인정보 보호 및 보안 아래쪽 "보안"에서 Jupjup이 차단되었다는 줄 옆 "그래도 열기"를 누릅니다.
   한 번 더 묻는 창에서 "그래도 열기"를 누르고 Mac 암호나 Touch ID로 확인하면 다음부터는 바로 열립니다.

3. 첫 실행 안내 창이 뜨면 화면 기록 권한을 켭니다.
   시스템 설정 › 개인정보 보호 및 보안 › 화면 및 시스템 오디오 녹음에서 Jupjup을 켠 뒤,
   안내 창의 "다시 열기"를 누릅니다(이 권한은 새로 켠 앱에만 적용돼요).

4. 메뉴 막대에 줍줍 아이콘이 보이면 끝. ⇧⌘2를 누르고 글자 위를 끌면 클립보드에 담깁니다.

요구 사항: macOS 14 이상 · 애플 실리콘 또는 인텔
읽은 글자·화면은 Mac 밖으로 나가지 않습니다. 오류·사용 통계(횟수만)는 메뉴에서 끌 수 있어요.
TXT
cat > "$STAGE/How to open.txt" <<'TXT'
Installing and opening Jupjup

1. Drag Jupjup.app into the Applications folder next to it.

2. Open Jupjup from Applications.
   Jupjup is not notarized by Apple yet, so the first launch is blocked.
   Close that dialog with "Done" (don't move it to the Trash), then go to
   System Settings › Privacy & Security, scroll to "Security" and click "Open Anyway" next to Jupjup.
   Confirm with "Open Anyway" and your password or Touch ID. From then on it opens normally.

3. When the welcome window appears, turn on Screen Recording:
   System Settings › Privacy & Security › Screen & System Audio Recording › Jupjup,
   then click "Reopen" in the welcome window (macOS applies this permission only to freshly launched apps).

4. Look for the Jupjup icon in the menu bar. Press ⇧⌘2, drag over any text, and it's on your clipboard.

Requires macOS 14 or later · Apple silicon or Intel
What Jupjup reads never leaves your Mac. Optional counts-only error & usage reports can be turned off in the menu.
TXT

rm -f "$DMG"
hdiutil create -volname "Jupjup" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
echo "made $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
