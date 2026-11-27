# 새 버전 내보내기

`make`를 치면 할 일 목록이 나온다. 순서:

1. `project.yml`의 `MARKETING_VERSION`(보이는 버전)과 `CURRENT_PROJECT_VERSION`(빌드 번호)을 올린다.
2. `make build` → `make test` — 모두 통과해야 한다.
3. `make dmg` → `build/Jupjup-<버전>.dmg` (Universal, "Jupjup Dev" 서명, 리포트 키 포함).
4. 릴리스 노트를 `docs/releases/<버전>.md`에 쓰고(영어 위, 한국어 아래, 처음 여는 방법 포함) 커밋한다.
5. `make release` — 태그를 달아 올리고, GitHub 릴리스를 만들어 DMG를 붙인다.
6. 소개 사이트(`nemodleo/jupjup-web`)는 알아서 따라온다. 릴리스가 올라가면 `notify-site` 워크플로가 사이트의 `sync-release`를 깨우고, 최신 릴리스를 읽어 버전·크기·링크와 `version.json`을 다시 만들어 커밋 → Cloudflare가 배포(1~2분). 혹시 놓쳐도 하루에 한 번 돈다. 손으로: `make site`.
   - 앱은 `version.json`을 켤 때와 하루에 한 번 읽어, 새 버전이면 메뉴 맨 위에 "새 버전 x.y · 내려받기"를 띄운다.
   - 새 버전마다 macOS 알림도 한 번 띄운다(`updateNotified`에 적어 두어 다시 안 띄움). 권한은 그때 처음 묻고, 고르기 화면·토스트가 떠 있으면 끝나고 5초 뒤로 미룬다.
   - 더 높은 macOS가 필요한 버전을 낼 때는 사이트 `version.json`에 `"min_os": "26"`처럼 넣어야 한다(사이트 저장소 `pages.py`가 쓰는 파일 — 아직 안 넣음). 그러면 낮은 맥에서는 메뉴 줄이 "macOS 26부터"가 되고, 눌러도 DMG 대신 시스템 설정 '소프트웨어 업데이트'가 열린다.
   - 손으로 확인: 지금보다 높은 버전을 넣은 파일을 만들어 `defaults write com.nemo.jupjup updateURL file:///…/version.json`, `defaults delete com.nemo.jupjup updateNotified` 뒤 앱을 다시 열면 10초쯤 안에 배너가 한 번 뜬다(다시 열면 안 뜸). 끝나면 `defaults delete com.nemo.jupjup updateURL`.
7. 확인: `curl -s https://jupjup.d-t-it.com/version.json`, 그리고 옛 버전이 깔린 맥에서 `make check-update`.

`notify-site`는 비밀값 `SITE_DISPATCH_TOKEN`(jupjup-web 하나에 Actions 읽기·쓰기만 준 fine-grained 토큰, 1년 만료)을 쓴다. 만료되면 같은 권한으로 다시 만들어 `gh secret set SITE_DISPATCH_TOKEN -R nemodleo/jupjup`.
