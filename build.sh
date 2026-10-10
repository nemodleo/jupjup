#!/bin/zsh
# 줍줍.app 빌드(Universal: 애플 실리콘 + 인텔) → /Applications(응용 프로그램)에 설치하고 다시 연다
# XcodeGen으로 프로젝트를 만들고 xcodebuild로 빌드한다(Sentry·TelemetryDeck 패키지 때문).
# 리포트 키는 report.env(git에 안 올림)에서 읽는다:
#   JJ_SENTRY_DSN=https://...@sentry.io/...
#   JJ_TELEMETRY_APP_ID=XXXXXXXX-XXXX-...
set -e
cd "$(dirname "$0")"
BUILD="${TMPDIR:-/tmp}/jupjup-build"   # iCloud 폴더 밖에서 빌드 (codesign xattr 문제)
[ -f report.env ] && source report.env
# 서명: tools/make_cert.sh로 만든 "Jupjup Dev"가 있으면 그걸로(빌드해도 화면 기록 권한이 유지됨), 없으면 애드혹(-)
IDENTITY="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q '"Jupjup Dev"' && IDENTITY="Jupjup Dev"
[ "$IDENTITY" = "-" ] && echo "애드혹 서명 (tools/make_cert.sh를 한 번 실행하면 권한이 안 풀림)"
xcodegen generate --quiet
xcodebuild -project Jupjup.xcodeproj -scheme Jupjup -configuration Release -derivedDataPath "$BUILD" \
  JJ_SENTRY_DSN="${JJ_SENTRY_DSN:-}" JJ_TELEMETRY_APP_ID="${JJ_TELEMETRY_APP_ID:-}" \
  -quiet build
APP="$BUILD/Build/Products/Release/Jupjup.app"
pkill -x Jupjup 2>/dev/null && sleep 1 || true
rm -rf /Applications/Jupjup.app && cp -R "$APP" /Applications/
# 빌드는 애드혹으로 하고(패키지 타깃까지 인증서를 강요하면 팀이 필요하다며 실패) 설치본만 다시 서명한다.
# 안쪽 프레임워크부터 같은 인증서로, 권한(entitlements)은 그대로
if [ "$IDENTITY" != "-" ]; then
  codesign --force --deep --sign "$IDENTITY" --preserve-metadata=entitlements,flags /Applications/Jupjup.app
fi
open /Applications/Jupjup.app
echo "설치됨: /Applications/Jupjup.app ($(lipo -archs /Applications/Jupjup.app/Contents/MacOS/Jupjup))"
