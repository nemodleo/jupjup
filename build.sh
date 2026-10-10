#!/bin/zsh
# 줍줍.app 빌드 → /Applications(응용 프로그램)에 설치하고 다시 연다
set -e
cd "$(dirname "$0")"
BUILD="${TMPDIR:-/tmp}/jupjup-build"; APP=$BUILD/Jupjup.app  # iCloud 폴더 밖에서 빌드 (codesign xattr 문제)
rm -rf $BUILD && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o $APP/Contents/MacOS/Jupjup \
  -framework AppKit -framework SwiftUI -framework Vision -framework VisionKit -framework ScreenCaptureKit -framework Carbon -framework ServiceManagement
cp -R Resources/Fonts $APP/Contents/Resources/
cp Resources/AppIcon.icns $APP/Contents/Resources/
cp -R Resources/Strings $APP/Contents/Resources/    # 화면 문구(언어별 JSON)
# 언어별 앱 이름(Finder·Dock): 한국어만 줍줍, 나머지는 Jupjup
LOCS=""
for f in Resources/Strings/*.json; do
  c=$(basename $f .json); mkdir -p $APP/Contents/Resources/$c.lproj
  if [ $c = ko ]; then n="줍줍"; else n="Jupjup"; fi
  printf 'CFBundleDisplayName = "%s";\n' "$n" > $APP/Contents/Resources/$c.lproj/InfoPlist.strings
  LOCS="$LOCS<string>$c</string>"
done
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Jupjup</string>
  <key>CFBundleDisplayName</key><string>줍줍</string>
  <key>CFBundleIdentifier</key><string>com.nemo.jupjup</string>
  <key>CFBundleExecutable</key><string>Jupjup</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>CFBundleLocalizations</key><array>$LOCS</array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
find $APP -exec xattr -c {} +  # 글꼴·아이콘 복사 때 붙은 iCloud 속성 제거
codesign --force --sign - $APP

pkill -x Jupjup 2>/dev/null && sleep 1 || true
rm -rf ~/Applications/Jupjup.app /Applications/Jupjup.app && cp -R $APP /Applications/
open /Applications/Jupjup.app
echo "설치됨: /Applications/Jupjup.app"
