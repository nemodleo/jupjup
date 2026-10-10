# Privacy Policy · 개인정보 처리방침

*Last updated: 2026-10-10 · [한국어](#한국어)*

## In one sentence

Jupjup reads text on your screen **on your Mac** and never saves, uploads or logs what it reads. The only thing that can leave your Mac is an optional, anonymous count of how the app is used and whether it crashed — and you can turn that off with one click.

## What Jupjup does with your screen

- When you press the shortcut, Jupjup takes a picture of the screen you selected, recognizes the text with Apple's on-device Vision or Live Text engines, and puts the text on your clipboard.
- The picture exists in memory only for that one capture and is discarded afterwards. It is never written to disk, never uploaded, never logged.
- The recognized text goes to your clipboard and nowhere else. The *Undo* button keeps a copy of your *previous* clipboard in memory until the notification closes, so it can be restored.
- Jupjup has no account, no server of its own, and no network access except for the optional reports described below.

## Optional error & usage reports

Jupjup can send anonymous reports to two services. This is **on by default** and shown on the first-run screen. You can turn it off at any time in the menu (*Send Error & Usage Reports*) or on the first-run screen. When it is off, nothing is sent.

### What is sent

Only **counts and categories**. Examples of real signals:

| Signal | What it contains |
|---|---|
| `app.launched` | interface language, mode (fast/accurate), chip (apple/intel) |
| `capture.started` / `capture.done` | mode, number of lines *as a range* (e.g. "2–5"), number of characters *as a range*, whether a table was found, time taken *as a range* (e.g. "<1 s") |
| `capture.empty` / `capture.cancelled` | mode |
| `toast.undo` / `toast.edit` / `toast.table` / `toast.join` | which button was used |
| `mode.changed` / `language.changed` / `shortcut.changed` | the new mode or language (not the shortcut keys) |
| `onboarding.shown` / `onboarding.done` | whether screen permission was granted |
| crash report | the type of crash and the code location inside Jupjup (stack trace), app version, macOS version, Mac model |

The complete list is in [`Sources/Reporting.swift`](Sources/Reporting.swift).

### What is never sent

- The text Jupjup recognized
- Screenshots or any image
- Where on the screen you selected, or which app was on screen
- Your clipboard
- Your name, email, Apple ID, or any account information
- Keystrokes (your chosen shortcut combination is not sent)

### Who receives it

- **Usage counts** go to [TelemetryDeck](https://telemetrydeck.com) ([their privacy policy](https://telemetrydeck.com/privacy/)). TelemetryDeck is built for privacy: it does not store IP addresses and identifies installs only by a salted, irreversible hash so counts are not double-counted.
- **Crash reports** go to [Sentry](https://sentry.io) ([their privacy policy](https://sentry.io/privacy/)). Jupjup disables Sentry's "default PII" option, so no IP address or user information is attached to reports.

Both services' SDKs also send standard technical fields such as app version, macOS version, Mac model and locale. Both services may see your IP address at the network level when a report arrives; Jupjup does not use it and TelemetryDeck does not store it.

### Builds without report keys

If Jupjup is built from source without report keys (`report.env`), the reporting code is inactive and nothing is sent at all, regardless of the setting.

## Permissions

- **Screen Recording** — required to see the screen you select. macOS asks you for it on first use; you can revoke it any time in *System Settings › Privacy & Security › Screen & System Audio Recording*.
- **Open at Login** — Jupjup registers itself as a login item on first run so the shortcut is always available. Turn it off in the menu.

## Children

Jupjup is a general productivity tool and does not knowingly collect any information from anyone, including children.

## Changes

If this policy changes, the date at the top changes and the new version is published in the repository.

## Contact

Open an issue at [github.com/nemodleo/jupjup](https://github.com/nemodleo/jupjup/issues).

---

# 한국어

*마지막 수정: 2026-10-10*

## 한 문장으로

줍줍은 화면의 글자를 **맥 안에서** 읽고, 읽은 내용을 저장하거나 올리거나 기록하지 않아요. 맥 밖으로 나갈 수 있는 건 "앱을 어떻게 썼는지, 죽었는지"의 익명 횟수뿐이고, 그것도 한 번의 클릭으로 끌 수 있어요.

## 화면을 어떻게 다루나요

- 단축키를 누르면 줍줍이 고른 영역의 화면 이미지를 찍고, 애플의 기기 안 인식 엔진(Vision 또는 라이브 텍스트)으로 글자를 읽어 클립보드에 담아요.
- 이미지는 그 한 번의 캡쳐 동안만 메모리에 있다가 버려져요. 디스크에 쓰지 않고, 올리지 않고, 기록하지 않아요.
- 읽은 글자는 클립보드로만 가요. *되돌리기* 버튼을 위해 **줍기 전** 클립보드 내용을 알림이 닫힐 때까지 메모리에 잠깐 들고 있어요.
- 줍줍에는 계정도 자체 서버도 없고, 아래 선택적 리포트 말고는 네트워크를 쓰지 않아요.

## 선택적 오류·사용 통계

줍줍은 익명 리포트를 두 서비스에 보낼 수 있어요. **기본값은 켬**이고 첫 실행 화면에서 보여 줘요. 메뉴의 *오류·사용 통계 보내기*나 첫 실행 화면에서 언제든 끌 수 있어요. 끄면 아무것도 보내지 않아요.

### 보내는 것

**횟수와 분류**뿐이에요. 실제 신호의 예는 이래요.

| 신호 | 담긴 것 |
|---|---|
| `app.launched` | 화면 언어, 모드(빠르게/정확하게), 칩(애플/인텔) |
| `capture.started` / `capture.done` | 모드, 줄 수 *구간*(예: "2–5"), 글자 수 *구간*, 표 여부, 걸린 시간 *구간*(예: "1초 미만") |
| `capture.empty` / `capture.cancelled` | 모드 |
| `toast.undo` / `toast.edit` / `toast.table` / `toast.join` | 어떤 버튼을 눌렀는지 |
| `mode.changed` / `language.changed` / `shortcut.changed` | 바뀐 모드나 언어 (단축키 조합은 보내지 않음) |
| `onboarding.shown` / `onboarding.done` | 화면 권한을 켰는지 |
| 오류 보고 | 오류 종류와 줍줍 코드 안의 위치(스택 트레이스), 앱 버전, macOS 버전, 맥 모델 |

전체 목록은 [`Sources/Reporting.swift`](Sources/Reporting.swift)에 있어요.

### 절대 보내지 않는 것

- 줍줍이 읽은 글자
- 스크린샷이나 어떤 이미지
- 화면의 어디를 골랐는지, 어떤 앱이 떠 있었는지
- 클립보드 내용
- 이름, 이메일, Apple ID 등 계정 정보
- 키 입력 (고른 단축키 조합도 보내지 않음)

### 누가 받나요

- **사용 횟수**는 [TelemetryDeck](https://telemetrydeck.com)([개인정보 정책](https://telemetrydeck.com/privacy/))으로 가요. 개인정보 보호를 위해 만들어진 서비스로, IP 주소를 저장하지 않고 설치를 되돌릴 수 없는 해시로만 구분해 중복 집계를 막아요.
- **오류 보고**는 [Sentry](https://sentry.io)([개인정보 정책](https://sentry.io/privacy/))로 가요. 줍줍은 Sentry의 "기본 개인정보" 옵션을 꺼 두어 IP 주소나 사용자 정보가 붙지 않아요.

두 서비스의 SDK는 앱 버전, macOS 버전, 맥 모델, 로케일 같은 표준 기술 정보도 함께 보내요. 리포트가 도착할 때 두 서비스가 네트워크 수준에서 IP 주소를 볼 수는 있지만, 줍줍은 쓰지 않고 TelemetryDeck은 저장하지 않아요.

### 리포트 키 없이 빌드하면

소스에서 리포트 키(`report.env`) 없이 빌드하면 리포트 코드가 꺼져서, 설정과 상관없이 아무것도 보내지 않아요.

## 권한

- **화면 기록** — 고른 화면을 보려면 필요해요. 처음 쓸 때 macOS가 물어보고, *시스템 설정 › 개인정보 보호 및 보안 › 화면 및 시스템 오디오 녹음*에서 언제든 끌 수 있어요.
- **맥을 켜면 함께 열기** — 단축키를 늘 쓸 수 있게 첫 실행 때 로그인 항목으로 등록해요. 메뉴에서 끌 수 있어요.

## 아동

줍줍은 일반 생산성 도구이며, 아동을 포함한 누구의 정보도 의도적으로 수집하지 않아요.

## 변경

이 방침이 바뀌면 맨 위의 날짜가 바뀌고 새 버전이 저장소에 올라가요.

## 문의

[github.com/nemodleo/jupjup](https://github.com/nemodleo/jupjup/issues)에 이슈를 남겨 주세요.
