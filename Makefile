# 줍줍 할 일 모음. `make`만 치면 목록이 나온다. 실제 일은 build.sh와 tools/ 스크립트가 한다.
SHELL   := /bin/zsh
VERSION := $(shell sed -nE 's/^ *MARKETING_VERSION: *//p' project.yml)
APP     := /Applications/Jupjup.app
DMG     := build/Jupjup-$(VERSION).dmg
NOTES   := docs/releases/$(VERSION).md
SNAP    ?= $(TMPDIR)jupjup-snap

.DEFAULT_GOAL := help
.PHONY: help build test dmg release site check-update snapshot cert icon clean

help: ## 이 목록
	@echo "줍줍 $(VERSION)"
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | awk -F'\t' '{printf "  make %-13s %s\n", $$1, $$2}'

build: ## Universal 빌드 → /Applications 설치·열기 (권한 유지하려면 먼저 make cert)
	./build.sh

test: ## 시험 전부(표·언어·QR·인증번호·화면 멈춤), 설치된 앱 기준
	tools/run_tests.sh $(APP)

dmg: ## 배포용 DMG → build/Jupjup-<버전>.dmg
	tools/make_dmg.sh

release: ## 태그 + GitHub 릴리스(DMG, docs/releases/<버전>.md) → 사이트·앱 알림이 따라옴
	@test -f $(DMG)   || { echo "$(DMG) 없음 — make dmg 먼저"; exit 1; }
	@test -f $(NOTES) || { echo "$(NOTES) 없음 — 릴리스 노트를 먼저 쓰세요"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "커밋 안 한 변경이 있어요"; exit 1; }
	git rev-parse -q --verify v$(VERSION) >/dev/null || git tag v$(VERSION)
	git push origin HEAD v$(VERSION)
	gh release create v$(VERSION) $(DMG) --title "Jupjup $(VERSION)" --notes-file $(NOTES)

site: ## 소개 사이트를 최신 릴리스로 바로 갱신(보통은 릴리스 때 자동)
	gh workflow run sync-release -R nemodleo/jupjup-web

check-update: ## 설치된 앱이 사이트의 새 버전을 알아보는지
	$(APP)/Contents/MacOS/Jupjup -checkupdate

snapshot: ## 화면 그림(메뉴·알림·기록…)을 임시 폴더에 그려 연다. 언어는 UI=en
	mkdir -p $(SNAP) && $(APP)/Contents/MacOS/Jupjup -snapshot $(SNAP) $(if $(UI),-lang $(UI)) && open $(SNAP)

cert: ## 자체 서명 인증서 "Jupjup Dev" 만들기(한 번만)
	tools/make_cert.sh

icon: ## 앱 아이콘 다시 그리기 → Resources/AppIcon.icns
	swift tools/make_icon.swift

clean: ## build/ 와 생성된 Xcode 프로젝트 지우기
	rm -rf build Jupjup.xcodeproj
