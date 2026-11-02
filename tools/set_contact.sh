#!/bin/zsh
# 연락 메일 바꾸기: make contact EMAIL=new@example.com
# CONTACT 한 곳이 기준이다. 저장소 문서(README·PRIVACY)의 옛 주소를 새 주소로 바꾸고 CONTACT를 고친다.
# 앱(줍줍에 대하여)은 다음 빌드 때 CONTACT를 Info.plist로 읽고, 소개 사이트는 다음 배포 때 GitHub의 CONTACT를 읽는다.
set -eu
cd "$(dirname "$0")/.."
NEW="${1:?새 주소를 주세요: make contact EMAIL=new@example.com}"
[[ "$NEW" == *@*.* ]] || { echo "메일 주소가 아니에요: $NEW"; exit 1; }
OLD=$(head -1 CONTACT)
[ "$OLD" = "$NEW" ] && { echo "이미 $NEW"; exit 0; }
for f in $(git grep -l -F "$OLD" -- ':!CONTACT'); do
  python3 -c 'import sys;p,o,n=sys.argv[1:];s=open(p).read();open(p,"w").write(s.replace(o,n))' "$f" "$OLD" "$NEW"
  echo "고침: $f"
done
print -r -- "$NEW" > CONTACT
echo "CONTACT: $OLD → $NEW  (커밋·푸시하면 사이트는 다음 배포에, 앱은 다음 빌드에 반영)"
