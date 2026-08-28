<div align="center">

# ApexTerm

**人間・パワーユーザー・Agent駆動ワークフローのための、Native macOS Terminal。**

普通のTerminalとしても、構造化されたコマンド履歴としても、Chatのような会話型コマンドUIとしても使えます。下にあるのは、あくまで本物のShellとPTYです。

[English](../README.md) · **日本語** · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [한국어](README.ko.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Native macOS](https://img.shields.io/badge/UI-Native%20macOS-3B82F6)
![Active development](https://img.shields.io/badge/status-active%20development-22C55E)

</div>

> [!IMPORTANT]
> ApexTermは現在も活発に開発中です。現時点の公開Repositoryは、完成された署名・Notarize済み配布チャンネルよりもSource Buildを主対象にしています。重要なTerminal workflowをDevelopment Buildで試す前には、必要なデータを保全してください。

## ApexTermを作る理由

Terminalには大きく2つの方向があります。

ひとつは、Shell・TUI・REPL・SSHなどを直接扱うための「生のTerminal」。もうひとつは、入力と出力を整理して、人間が後から読みやすくする高レベルなコマンドUIです。

ApexTermは、この2つを分離しません。

- **本物のTerminal**としてShell、TUI、REPL、tmux、SSH、PTY前提のツールをそのまま使える。
- コマンド履歴を**構造化Transcript**として読みやすく表示できる。
- 必要なときだけ**Cモード**へ切り替え、Chatのように入力と出力を分離できる。
- Terminalが壊れたように見える場面でも、偽のPromptを表示せず**実Processを復旧**する。
- 時間指定送信、Shortcut、Local Automation、任意のAgent連携を使いつつ、Terminal本体は独立して動く。

![ApexTermのタブ、分割ペイン、Command Transcript](images/overview.png)

## 4つの表示モード、Shellは1つ

ApexTermには4つのTerminal表示モードがあります。変わるのは表示・操作レイヤーで、裏のPTY Sessionを別物へ置き換えるわけではありません。

| Mode | 表示 | 向いている用途 |
| --- | --- | --- |
| **On** | 全Command Transcript + Live Terminal | 長い作業を後から確認しながらTerminalも見たいとき |
| **Off** | Live Terminalのみ | TUI、REPL、最大表示領域、従来型Terminal操作 |
| **Ex** | 最新1件の完了コマンド/出力 + Live Terminal | 最新結果だけに集中したいとき |
| **C** | 会話型のCommand Card + 専用入力欄 | 入力と出力を明確に分離して進めたいとき |

上部の切替ボタン、または設定可能な **Cycle Transcript Mode** Shortcutから切り替えられます。

### Cモード: Shell Commandのための会話UI

Cモードは、TextFieldの裏でTerminalらしい文字列を捏造する機能ではありません。送信したCommandは実Terminal Sessionで実行され、その周囲の操作・表示だけを会話型に再構成します。

- 送信した**入力は右側**。
- Commandの**出力は左側**。
- 既定は **`⌘↩` で送信**。Shortcutは設定で変更可能。
- Shell実行中は送信をLockし、**実Promptへの復帰を検出してから**再度送信可能になる。
- 長い入力・出力は、設定した **1〜8行**のPreviewへ折り畳める。
- Cardを展開せず、入力・出力・両方をCopyできる。
- Cモードの会話領域は、非表示になったLive Terminalとは独立してScrollする。
- 狭いPaneから広いWindowまで、固定幅ではなくResponsiveに追従する。
- Commandを**指定時刻に予約送信**できる。予定時刻にShellがBusyなら、実行中Programへ文字列を流し込まずPrompt復帰を待つ。

目的は単純です。Shellの実状態を偽らず、Command workflowだけを読みやすくします。

## 出力を「使える情報」にする

ApexTermではCommand出力を、ただ画面に流れて消える文字列ではなく、Copy・検索・再確認する対象として扱います。

### 出力を1クリックでCopy

完了したCommand Cardには直接Copyボタンがあります。Copyを押してもCardの開閉状態は変わりません。

### 出力の自動Copy

**Automatically copy command output** をONにすると、空でないCommand出力を完了時にClipboardへ自動Copyします。

Copy完了時にはmacOS画面中央へToastを表示します。Settingsから以下を調整できます。

- **Size:** 80〜200%
- **Display time:** 0.5〜5.0秒
- **Transparency:** 0〜55%
- Commandを実行しなくても確認できる **Preview** ボタン

### 強制停止とTerminal復旧

Foreground ProgramやTUIが固まった場合、ApexTermはPromptに見える文字列を表示して終わりにはしません。

Local PTYではForeground Process GroupへのInterrupt、必要に応じた段階的な停止、Terminal/TTY Modeの復旧を行い、本物のShellがInteractiveな状態へ戻ることを目指します。Shell自体が終了済みなら、存在しないProcessへ`Ctrl+C`を送り続けるのではなくSession再起動へ切り替えます。

## Workspace・Pane・Tab

複数Terminalを扱うために、画面をただ細かく割り続けるだけの設計にはしていません。

- Workspace Tab
- 複数Terminal ColumnとNested Split
- 各Column内のTerminal Tab
- Tab / PaneのDrag・並び替え
- Tab / Pane移動Shortcut
- Active / Inactive TerminalのFocus制御
- 幅が狭い場合のCompact icon-only Tab

![狭いWindowでのCompact Tab](images/compact-tabs.png)

## SSH・EC2・tmux

Remote操作もTerminal本体と同じ一級Workflowとして扱います。

- SSH Host Profile
- Local / Remote tmux workflow
- SSH SessionへのInteractive TTY割り当て
- Remoteを考慮したTranscript Mode
- 明示的なOverrideがなければRemote Sessionを自動で **Ex** 表示
- `ssh`、`tailscale ssh`、`mosh`、`aws ssm start-session`、`gcloud compute ssh`などのInteractive Remote Commandを検出
- Local OSC 133 Shell Integrationが入っていないRemote Shell向けPrompt readiness fallback

Remoteから流れてくるEscape Sequenceには、Local Outputより厳しいTrust Policyを適用します。

## 検索とCommand History

### Universal Search

**`⌘K`** でWorkspace、Terminal Session、Command、Agent Chat、Agent Eventを横断検索できます。

![Universal Search](images/universal-search.png)

### Command Timeline

Shell CommandとAgent ActivityをひとつのTimelineで確認できます。Kind、Failure、Session、Queryで絞り込み可能です。

Markdown Exportは以下に対応します。

- Metadataのみ
- Redacted
- Full Output

![Command Timeline](images/command-timeline.png)

## TerminalのためのSettings

高頻度で触るTerminal挙動をSource Codeに埋め込まず、Settingsから変更できます。

- Application Language
- System / Light / Dark Appearance
- Accent Color
- Terminal / Sidebar Font Size
- Input / Output Color
- `On / Off / Ex / C`
- Cモード折り畳みPreview行数
- Smart Paste Protection
- Multi-line Paste Confirmation
- Secure Keyboard Entry
- 出力自動CopyとNotification Design
- Large Outputの自動折り畳み
- Keyboard Shortcut
- Toolbar / Buttonの表示・並び
- Remote Host
- Optional DevSpace Integration

![ApexTerm Settings](images/settings.png)

## Keyboard Shortcut

Shortcutは **Settings → Keybindings** から変更できます。主な既定値は以下です。

| Action | Default |
| --- | ---: |
| Universal Search | `⌘K` |
| Quick Terminal | <kbd>⌃</kbd><kbd>&#96;</kbd> |
| Cモード送信 | `⌘↩` |
| 最新Terminal出力をCopy | `⌥⌘C` |
| `On / Off / Ex / C`切替 | `⌥⌘T` |
| Command Timeline | `⇧⌘Y` |
| 次のMain Tab | `⌃⇥` |
| 前のMain Tab | `⌃⇧⇥` |
| 次のTerminal Tab | `⇧⌘]` |
| 前のTerminal Tab | `⇧⌘[` |

Shortcut変更のためにSource Codeを編集する必要はありません。

## Architecture

ApexTermはWeb TerminalをDesktop Shellで包んだアプリではなく、Native macOS Applicationです。

| Layer | Technology / Responsibility |
| --- | --- |
| UI | SwiftUI。Native挙動が必要な箇所はAppKit |
| Terminal Rendering | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) |
| Process I/O | Real PTY Session + Process Group Control |
| Shell Semantics | OSC 133 Shell Integration + bounded Prompt fallback |
| Persistence | Local Settings、SQLite-backed Command/Event History |
| Multiplexing | tmux Integration |
| Automation | Capability / Risk-aware Local Automation + `apextermctl` |
| Optional Agent Bridge | Terminal Coreから分離したDevSpace |

重要な設計原則のひとつは、**Presentation StateとProcess Stateを分離すること**です。UIだけ緑色にして、実際には死んでいるPTYやShellを「復旧済み」に見せることは避けます。

## Requirements

- **macOS 14以降**
- **Swift 6.2を扱えるXcode Command Line Tools**

## SourceからInstall

Terminal本体を利用するためのAccountやCloud Serviceは不要です。

```zsh
git clone https://github.com/uniplanck/ApexTerm.git
cd ApexTerm
zsh scripts/install-app.zsh
```

InstallerはAppをBuildし、書込み可能なら`/Applications/ApexTerm.app`へ、そうでなければ`~/Applications/ApexTerm.app`へInstallします。Launch Servicesへの登録と、安全に置換可能な場合は`~/.local/bin/gag`へのbundled CLI link作成も行います。

### InstallせずBuild

```zsh
swift build --product ApexTerm
zsh scripts/build-app.zsh
```

App Bundleは既定で以下へ出力されます。

```text
.artifacts/ApexTerm.app
```

## README Screenshotを再生成

RepositoryにはREADME用Screenshot生成Scriptがあります。

```zsh
zsh scripts/capture-readme-screenshots.zsh
```

通常利用中のApexTerm Sessionを意図的に再利用せず、隔離したDemo Buildを起動して`docs/images/`へ画像を書き出します。

## Optional DevSpace Companion

ApexTerm単体でTerminal機能は動作します。

ChatGPTなどのCompatible Clientから、明示的に許可したLocal ProjectをInspect/Editしたい場合は、Public DevSpace forkを任意で利用できます。

- [uniplanck/devspace](https://github.com/uniplanck/devspace)

DevSpaceは別ProcessのSelf-hosted MCP Serverです。ApexTermのTerminal、Pane、Tab、Command History、Cモード、Shortcut、tmux、SSH、Local Automationには**必須ではありません**。

Setup入口は **ApexTerm → Settings → DevSpace** にあります。

## Security Model

TerminalはShell、File、Credential、Remote Machineへ直結するため、便利機能ほど境界が必要です。

- Remote Escape SequenceはTrusted Local Outputより厳しく扱う。
- Default Trust PolicyではRemote OSC Clipboard AccessをBlock。
- Smart PasteはRisky / Multi-line Payloadの確認を要求可能。
- DevSpaceは任意機能で、意図して公開するFolderだけを許可する。
- API Key、Cookie、Private Key、`.env`、Local Auth MaterialをCommitしない。
- Commit、Push、Deploy、Publish前にCommandとRepository変更を確認する。

## Development

Public `main` branchをSource of Truthとします。

Focused Changeでは以下を推奨します。

1. Feature Branchを作成。
2. 無関係なWorking Tree変更を壊さない。
3. 対象範囲をBuild/Test。
4. PTY、Input、Focus、Terminal Renderingに触れる変更では関連Runtime E2Eも実行。
5. Build ProductやMachine-local設定をGitへ入れない。

主な検証Command:

```zsh
swift test
swift build --product ApexTerm
zsh scripts/terminal-interaction-e2e.zsh
```

再現可能なTerminal ScenarioとmacOS / Shell / tmux Versionが書かれたIssue・Focused Pull Requestは特に歓迎します。

## Current Direction

ApexTermはまだ高速に進化しています。現在の優先事項は以下です。

- Terminal / PTY / TUI CompatibilityとRecovery
- CモードのInteraction Quality
- Remote / tmux Workflow
- 高速なMulti-pane Navigation
- より安全なAutomation Surface
- Packaging、Documentation、Accessibility、Release Quality

## Project Status

ApexTermは**Active Development Software**です。実Terminal workloadから出てくるEdge Caseに合わせ、ArchitectureやUXが変わる可能性があります。

ApexTermが役に立った場合、RepositoryへのStarと、再現手順のあるFocused Issueが現時点では最も有用なFeedbackです。
