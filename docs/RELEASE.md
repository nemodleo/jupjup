# 새 버전 내보내기

1. `project.yml`의 `MARKETING_VERSION`(보이는 버전)과 `CURRENT_PROJECT_VERSION`(빌드 번호)을 올린다.
2. `tools/run_tests.sh /Applications/Jupjup.app` — 모두 통과해야 한다(`./build.sh`로 설치한 뒤).
3. `tools/make_dmg.sh` → `build/Jupjup-<버전>.dmg` (Universal, "Jupjup Dev" 서명, 리포트 키 포함).
4. `git tag v<버전> && git push origin v<버전>`
5. GitHub 릴리스에 DMG를 붙여 올린다(파일 이름 `Jupjup-<버전>.dmg` 그대로):
   `gh release create v<버전> build/Jupjup-<버전>.dmg --title "Jupjup <버전>" --notes-file <노트>`
6. 소개 사이트(`nemodleo/jupjup-web`)는 한 시간 안에 `sync-release`가 최신 릴리스를 읽어 버전·크기·링크와 `version.json`을 다시 만들고 커밋 → Cloudflare가 배포. 바로 하려면
   `gh workflow run sync-release -R nemodleo/jupjup-web`
   - 앱은 `version.json`을 켤 때와 하루에 한 번 읽어, 새 버전이면 메뉴 맨 위에 "새 버전 x.y · 내려받기"를 띄운다.
7. 확인: `curl -s https://jupjup.d-t-it.com/version.json`, 그리고 설치된 옛 버전에서 `/Applications/Jupjup.app/Contents/MacOS/Jupjup -checkupdate`.
