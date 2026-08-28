<div align="center">

# ApexTerm

**A native macOS terminal built for humans, power users, and agent-driven workflows.**

Use it as a traditional terminal, a structured command transcript, or a conversation-style command interface without giving up the real shell underneath.

**English** · [日本語](docs/README.ja.md) · [简体中文](docs/README.zh-Hans.md) · [繁體中文](docs/README.zh-Hant.md) · [한국어](docs/README.ko.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Native macOS](https://img.shields.io/badge/UI-Native%20macOS-3B82F6)
![Active development](https://img.shields.io/badge/status-active%20development-22C55E)

</div>

> [!IMPORTANT]
> ApexTerm is under active development. The public repository currently targets source builds rather than a polished signed/notarized release channel. Back up important workflows before testing development builds.

## Why ApexTerm?

Most terminals make you choose between two worlds: a raw terminal that is excellent for direct interaction, or a higher-level command UI that is easier to review but no longer feels like a real shell.

ApexTerm keeps both.

- **Use the real terminal** for shells, TUIs, REPLs, tmux, SSH, and everything that expects a PTY.
- **Turn command history into a structured transcript** when you want readable input/output blocks.
- **Switch into C mode** when a conversation-style command flow is faster than scanning terminal escape sequences and prompts.
- **Recover from stuck terminal states** without pretending a dead shell is healthy.
- **Automate carefully** with scheduled commands, configurable shortcuts, bounded local automation, and optional agent workflows.

![ApexTerm tabs, split panes, and command transcripts](docs/images/overview.png)

## Four terminal views, one real shell

ApexTerm has four presentation modes. They change how terminal activity is presented; they do not replace the underlying PTY session.

| Mode | What you see | Good for |
| --- | --- | --- |
| **On** | Full command transcript plus the live terminal | Reviewing longer command sessions while keeping the terminal visible |
| **Off** | The live terminal only | TUIs, REPLs, maximum terminal space, traditional workflows |
| **Ex** | Only the latest completed command/output plus the live terminal | Staying focused on the current result without a long transcript |
| **C** | Conversation-style command cards and a dedicated composer | Command-driven work where readable input/output separation matters most |

Cycle them from the terminal toolbar or use the configurable **Cycle Transcript Mode** shortcut.

### C mode: a conversation UI for shell commands

C mode is not a fake shell pasted on top of a text field. Commands still execute in the terminal session; ApexTerm changes the interaction layer around them.

- Sent commands appear on the **right**.
- Command output appears on the **left**.
- The composer sends with **`⌘↩` by default**, and the shortcut is configurable.
- Sending is locked while the shell is busy and re-enabled when ApexTerm detects a real prompt boundary.
- Long command/output cards collapse to a configurable **1–8 line** preview.
- Input, output, or both can be copied without expanding the card.
- The conversation scrolls independently from the hidden live terminal surface.
- The layout adapts from narrow panes to wide windows instead of staying at a fixed chat width.
- Commands can be **scheduled for a future time**; if the prompt is still busy, ApexTerm waits instead of blindly typing into a running program.

The goal is simple: make shell work easier to read without lying about the state of the shell.

## Command output that is easier to use

ApexTerm treats command output as something you often want to inspect, copy, search, and revisit.

### One-click output copy

Completed command cards expose direct copy controls. Clicking the copy button copies output without also opening or collapsing the card.

### Automatic output copy

Enable **Automatically copy command output** and a completed command with non-empty output replaces the clipboard automatically.

A centered macOS toast confirms the copy. Its presentation is configurable from Settings:

- **Size:** 80–200%
- **Display time:** 0.5–5.0 seconds
- **Transparency:** 0–55%
- Built-in **Preview** button for tuning the notification without running a command

### Force interrupt and recovery

When a foreground program or TUI stops responding, ApexTerm provides an explicit recovery action rather than merely printing a prompt-looking string.

For local PTY sessions, recovery can interrupt the foreground process group, escalate when necessary, restore terminal/TTY modes, and bring the real shell back to an interactive state. If the shell itself has already exited, the session can be restarted instead of sending `Ctrl+C` into a process that no longer exists.

## Workspaces, panes, tabs, and navigation

ApexTerm is designed around working with several terminal contexts without turning the window into a spreadsheet of tiny shells.

- Workspace tabs
- Multiple terminal columns and nested split layouts
- Terminal tabs inside each column
- Drag/reorder workflows for tabs and panes
- Configurable tab and pane navigation shortcuts
- Active/inactive terminal focus handling
- Compact icon-only tabs when horizontal space gets tight

![Compact ApexTerm window with icon-only separated tabs](docs/images/compact-tabs.png)

## Remote and tmux workflows

Remote work is a first-class terminal workflow rather than a special side panel.

- SSH host profiles
- Local and remote tmux workflows
- Interactive TTY allocation for SSH sessions
- Remote-aware transcript behavior
- Automatic **Ex** presentation for remote sessions unless you explicitly choose another mode
- Detection for common interactive remote commands such as `ssh`, `tailscale ssh`, `mosh`, `aws ssm start-session`, and `gcloud compute ssh`
- Prompt-readiness fallback for remote shells that do not have ApexTerm's local OSC 133 shell integration installed

Remote terminal data also passes through stricter trust policies before host-side features such as clipboard access are allowed.

## Search and command history

### Universal Search

Press **`⌘K`** to search across workspaces, terminal sessions, commands, agent chats, and agent events from one bounded in-memory snapshot.

![Universal Search across workspaces, sessions, and commands](docs/images/universal-search.png)

### Command Timeline

The Command Timeline combines shell commands and agent activity into one review surface. Filter by kind, failure state, session, and query.

Markdown export supports:

- Metadata-only export
- Redacted export
- Full-output export

![Command Timeline combining commands and agent events](docs/images/command-timeline.png)

## Settings that belong in a terminal

ApexTerm keeps high-frequency terminal behavior configurable instead of hard-coding one author's preferences as universal truth.

Configure:

- Application language
- System / light / dark appearance
- Accent color
- Terminal and sidebar font sizes
- Input/output colors
- `On / Off / Ex / C` presentation
- C-mode collapsed preview line count
- Smart paste protection
- Multi-line paste confirmation
- Secure keyboard entry
- Automatic output copy and its notification appearance
- Automatic collapsing of large outputs
- Keyboard shortcuts
- Toolbar/button visibility and ordering
- Remote hosts
- Optional DevSpace integration

![ApexTerm Settings](docs/images/settings.png)

## Keyboard shortcuts

Shortcuts are configurable in **Settings → Keybindings**. These are the current defaults for several high-frequency actions:

| Action | Default |
| --- | ---: |
| Universal Search | `⌘K` |
| Quick Terminal | <kbd>⌃</kbd><kbd>&#96;</kbd> |
| Send in C mode | `⌘↩` |
| Copy latest terminal output | `⌥⌘C` |
| Cycle `On / Off / Ex / C` | `⌥⌘T` |
| Command Timeline | `⇧⌘Y` |
| Next main tab | `⌃⇥` |
| Previous main tab | `⌃⇧⇥` |
| Next terminal tab | `⇧⌘]` |
| Previous terminal tab | `⇧⌘[` |

Shortcut fields can be rebound from Settings rather than requiring source edits.

## Architecture

ApexTerm is a native macOS application rather than a web terminal wrapped in a desktop shell.

| Layer | Technology / responsibility |
| --- | --- |
| UI | SwiftUI with AppKit where native behavior is required |
| Terminal rendering | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) |
| Process I/O | Real PTY sessions and process-group control |
| Shell semantics | OSC 133 shell integration plus bounded prompt fallbacks |
| Persistence | Local settings, SQLite-backed command/event history |
| Multiplexing | tmux integration |
| Automation | Local capability/risk-aware automation surfaces and `apextermctl` |
| Optional agent bridge | DevSpace, kept separate from core terminal functionality |

ApexTerm deliberately separates **presentation state** from **process state**. A green-looking UI should not be allowed to invent a healthy prompt when the PTY or shell has actually died.

## Requirements

- **macOS 14 or later**
- **Xcode command-line tools with Swift 6.2 support**

## Install from source

There is no required account or cloud service for the terminal itself.

```zsh
git clone https://github.com/uniplanck/ApexTerm.git
cd ApexTerm
zsh scripts/install-app.zsh
```

The installer builds the app, installs it to `/Applications/ApexTerm.app` when writable (otherwise `~/Applications/ApexTerm.app`), registers it with Launch Services, and installs the bundled `gag` CLI link at `~/.local/bin/gag` when safe to do so.

### Build without installing

```zsh
swift build --product ApexTerm
zsh scripts/build-app.zsh
```

The local app bundle is written to:

```text
.artifacts/ApexTerm.app
```

## Regenerate README screenshots

The repository includes deterministic README screenshot tooling:

```zsh
zsh scripts/capture-readme-screenshots.zsh
```

It launches an isolated demo build and writes presentation-ready images to `docs/images/` without intentionally reusing the normal running ApexTerm session.

## Optional DevSpace companion

ApexTerm works on its own.

Developers who want ChatGPT or another compatible client to inspect and edit explicitly allowed local projects can optionally run the public DevSpace fork:

- [uniplanck/devspace](https://github.com/uniplanck/devspace)

DevSpace is a separate self-hosted MCP server. It is **not required** for ApexTerm's terminal, panes, tabs, command history, C mode, shortcuts, tmux, SSH, or local automation features.

A setup entry is available in **ApexTerm → Settings → DevSpace**.

## Security model

Terminals sit directly on top of your shell, files, credentials, and remote machines, so convenience features need boundaries.

- Remote escape sequences are treated more strictly than trusted local terminal output.
- Remote OSC clipboard access is blocked by the default trust policy.
- Smart paste can require confirmation for risky or multi-line payloads.
- DevSpace is optional and should only receive access to folders you intentionally expose.
- Do not commit API keys, cookies, private keys, `.env` files, or local authentication material.
- Review commands and repository changes before committing, pushing, deploying, or publishing.

## Development

The public `main` branch is the source of truth.

For focused changes:

1. Create a feature branch.
2. Keep unrelated working-tree changes intact.
3. Build and test the affected area.
4. Run the relevant terminal/runtime E2E path when behavior touches PTY, input, focus, or terminal rendering.
5. Keep generated build products and machine-local configuration out of Git.

Useful commands:

```zsh
swift test
swift build --product ApexTerm
zsh scripts/terminal-interaction-e2e.zsh
```

Issues and focused pull requests are welcome, especially when they include a reproducible terminal scenario and the macOS/shell/tmux versions involved.

## Current direction

ApexTerm is still moving quickly. Current priorities are intentionally practical:

- Terminal / PTY / TUI compatibility and recovery
- C-mode interaction quality
- Remote and tmux workflows
- Fast multi-pane navigation
- Safer automation surfaces
- Packaging, documentation, accessibility, and release quality

## Project status

ApexTerm is **active development software**. The architecture and UX may change as real terminal workloads expose edge cases.

If ApexTerm is useful to you, starring the repository and opening focused issues with reproducible examples are the most useful forms of feedback right now.
