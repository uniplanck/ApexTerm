# ApexTerm

[English](../README.md) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · **한국어**

ApexTerm은 탭, 분할 패널, 명령 기록, 검색 가능한 히스토리, tmux, 사용자 지정 단축키와 선택형 Agent 개발 연동을 하나로 묶은 네이티브 macOS 터미널 워크스페이스입니다.

> ApexTerm은 현재 활발히 개발 중입니다. 개발 빌드를 시험하기 전에 중요한 터미널 작업을 저장하세요.

## 화면과 주요 기능

![ApexTerm 탭, 3분할 패널, 명령 기록](images/overview.png)

- 탭과 중첩 분할 패널
- 변경 가능한 탭·패널 이동 단축키
- On / Off / Ex 명령 기록 모드
- 활성 패널의 최신 출력 복사와 완료 알림
- 작은 창에서 자동으로 전환되는 원형 아이콘 탭
- tmux 세션과 원격 호스트 프로필

### 통합 검색

![워크스페이스, 세션, 명령을 검색하는 Universal Search](images/universal-search.png)

`⌘K`로 Workspace, Terminal Session, Command, Agent Chat, Agent Event를 한 번에 검색할 수 있습니다.

### Command Timeline

![명령과 Agent Event를 함께 보여 주는 Command Timeline](images/command-timeline.png)

종류, 실패 상태, 세션, 검색어로 필터링할 수 있습니다. Markdown 내보내기는 메타데이터 전용, 비밀정보 마스킹, 전체 출력 모드를 지원합니다.

### 설정과 언어

![언어, 터미널, 명령 기록 설정](images/settings.png)

Settings에서 앱 언어, 인터페이스 모양, 강조 색상, 터미널 동작, 명령 기록, 사이드바, 단축키, UI 컨트롤, 원격 호스트와 선택형 DevSpace 안내를 변경할 수 있습니다.

### 컴팩트 탭

![작은 창의 원형 아이콘 탭](images/compact-tabs.png)

공간이 좁아지면 탭 이름이 원형 아이콘으로 자동 전환되고, 구분선으로 각 탭을 명확하게 식별할 수 있습니다.

## 요구 사항

- macOS 14 이상
- Swift 6.2를 지원하는 Xcode Command Line Tools

## 빌드

```zsh
swift build --product ApexTerm
zsh scripts/build-app.zsh
```

서명된 로컬 앱은 기본적으로 `.artifacts/ApexTerm.app`에 생성됩니다.

## README 스크린샷 다시 생성

```zsh
zsh scripts/capture-readme-screenshots.zsh
```

스크립트는 격리된 데모 앱을 실행하고 ApexTerm의 다크 인터페이스를 유지한 채 다섯 개의 기능 장면을 둥근 흰색 프레젠테이션 배경에 배치해 `docs/images/`에 저장합니다. 평소 사용 중인 ApexTerm 세션은 종료하거나 변경하지 않습니다.

## 선택형 DevSpace 연동

ApexTerm은 단독으로 사용할 수 있습니다. ChatGPT가 명시적으로 허용한 로컬 프로젝트를 확인하고 편집하게 하려면 공개 DevSpace fork를 선택적으로 설정할 수 있습니다.

- [uniplanck/devspace](https://github.com/uniplanck/devspace)

DevSpace는 별도로 셀프 호스팅하는 MCP 서버이며, ApexTerm의 터미널, 탭, 패널, 기록, 단축키 또는 tmux 기능에는 필요하지 않습니다.

## 보안

API 키, 쿠키, 개인 키, `.env`, 로컬 인증 파일을 커밋하지 마세요. DevSpace에는 의도적으로 공개할 프로젝트 폴더만 허용하세요.
