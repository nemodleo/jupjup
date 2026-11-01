# 새 버전 내보내기

`make`를 치면 할 일 목록이 나온다. 순서:

1. `project.yml`의 `MARKETING_VERSION`(보이는 버전)과 `CURRENT_PROJECT_VERSION`(빌드 번호)을 올린다.
2. `make build` → `make test` — 모두 통과해야 한다.
3. `make dmg` → `build/Jupjup-<버전>.dmg` (Universal, "Jupjup Dev" 서명, 리포트 키 포함).
4. 릴리스 노트를 `docs/releases/<버전>.md`에 쓰고(영어 위, 한국어 아래, 처음 여는 방법 포함) 커밋한다.
5. `make release` — 태그를 달아 올리고, GitHub 릴리스를 만들어 DMG를 붙인다.
6. 소개 사이트(`nemodleo/jupjup-web`)는 알아서 따라온다. 릴리스가 올라가면 `notify-site` 워크플로가 사이트의 `sync-release`를 깨우고, 최신 릴리스를 읽어 버전·크기·링크와 `version.json`을 다시 만들어 커밋 → Cloudflare가 배포(1~2분). 혹시 놓쳐도 하루에 한 번 돈다. 손으로: `make site`.
   - 앱은 `version.json`을 켤 때와 하루에 한 번 읽어, 새 버전이면 메뉴 맨 위에 "새 버전 x.y · 내려받기"를 띄운다.
7. 확인: `curl -s https://jupjup.d-t-it.com/version.json`, 그리고 옛 버전이 깔린 맥에서 `make check-update`.

`notify-site`는 비밀값 `SITE_DISPATCH_TOKEN`(jupjup-web 하나에 Actions 읽기·쓰기만 준 fine-grained 토큰, 1년 만료)을 쓴다. 만료되면 같은 권한으로 다시 만들어 `gh secret set SITE_DISPATCH_TOKEN -R nemodleo/jupjup`.
