#!/bin/zsh
# 시험 네 가지를 한 번에: 표 채점(HTML 표 8종, 칸 기준) · 12개 언어 인식 · QR 스타일 15종 · 인식 중 화면 멈춤.
# 로컬: tools/run_tests.sh [설치된 앱 경로]   CI: .github/workflows/ci.yml 이 같은 스크립트를 쓴다.
# 하나라도 기준 아래면 종료 코드 1.
set -u
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/jupjup-tests"
rm -rf "$OUT" && mkdir -p "$OUT/table" "$OUT/lang" "$OUT/code" "$OUT/img" "$OUT/qr"
APP="${1:-/Applications/Jupjup.app}"
fail=0

echo "=== 1. 표 채점 (기준 95%)"
cp tools/table_bench.swift "$OUT/table/main.swift"
swiftc -O Sources/Recognizer.swift "$OUT/table/main.swift" -framework WebKit -o "$OUT/table_bench" 2>&1 | grep -E "error" && fail=1
"$OUT/table_bench" "$OUT/img" 95 | tail -4 || fail=1

echo "=== 2. 12개 언어 인식 (언어마다 기준 95%)"
cp tools/lang_bench.swift "$OUT/lang/main.swift"
swiftc -O Sources/Recognizer.swift "$OUT/lang/main.swift" -o "$OUT/lang_bench" 2>&1 | grep -E "error" && fail=1
"$OUT/lang_bench" 95 || fail=1

echo "=== 3. QR 스타일 15종 (기준 13개)"
cp tools/code_bench.swift "$OUT/code/main.swift"
swiftc -O Sources/Recognizer.swift "$OUT/code/main.swift" -o "$OUT/code_bench" 2>&1 | grep -E "error" && fail=1
"$OUT/code_bench" "$OUT/qr" 13 | tail -3 || fail=1

echo "=== 4. 인식 중 화면 멈춤 (기준 1000ms)"
if [ -x "$APP/Contents/MacOS/Jupjup" ]; then
  line=$("$APP/Contents/MacOS/Jupjup" -benchocr 2>/dev/null)
  echo "$line"
  ms=$(echo "$line" | sed -nE 's/.*멈춤 ([0-9]+)ms.*/\1/p')
  if [ -z "$ms" ]; then echo "측정 실패"; fail=1
  elif [ "$ms" -gt 1000 ]; then echo "← 기준 초과"; fail=1; fi
else
  echo "앱 없음: $APP (건너뜀)"
fi

[ $fail -eq 0 ] && echo "=== 모두 통과" || echo "=== 실패 있음"
exit $fail
