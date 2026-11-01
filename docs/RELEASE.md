# 새 버전 내보내기

1. `project.yml`의 `MARKETING_VERSION`(보이는 버전)과 `CURRENT_PROJECT_VERSION`(빌드 번호)을 올린다.
2. `tools/run_tests.sh /Applications/Jupjup.app` — 모두 통과해야 한다(`./build.sh`로 설치한 뒤).
3. `tools/make_dmg.sh` → `build/Jupjup-<버전>.dmg` (Universal, "Jupjup Dev" 서명, 리포트 키 포함).
4. 소개 사이트(`~/Documents/money/jupjup-web`)에서 `npm run deploy`
   - 가장 최근 DMG를 `web/download/`로 가져오고, `pages.py`가 버전·크기·링크와 `web/version.json`을 새로 쓴 뒤 배포한다.
   - 앱은 `version.json`을 켤 때와 하루에 한 번 읽어, 새 버전이면 메뉴 맨 위에 "새 버전 x.y · 내려받기"를 띄운다.
5. 확인: `/Applications/Jupjup.app/Contents/MacOS/Jupjup -checkupdate` (설치된 옛 버전에서 새 버전이 보이면 끝).
6. `git tag v<버전> && git push --tags`
