# ApexTerm

**English** · [日本語](docs/README.ja.md) · [简体中文](docs/README.zh-Hans.md) · [繁體中文](docs/README.zh-Hant.md) · [한국어](docs/README.ko.md)

ApexTerm is a native macOS terminal workspace for fast tab and pane navigation, command transcripts, searchable history, tmux workflows, configurable shortcuts, and optional agent-assisted development.

> ApexTerm is under active development. Back up important terminal workflows before testing development builds.

## Product tour

![ApexTerm tabs, a three-pane workspace, and command transcripts](docs/images/overview.png)

- Tabs plus nested split panes
- Configurable keyboard navigation for tabs and panes
- On / Off / Ex command-transcript modes
- Copy the active pane's latest output with an on-screen confirmation
- Compact icon-only tabs for small windows
- tmux sessions and remote-host profiles

### Universal Search

![Universal Search across workspaces, sessions, and commands](docs/images/universal-search.png)

Press `⌘K` to search across workspaces, terminal sessions, commands, agent chats, and agent events from one bounded in-memory snapshot.

### Command Timeline

![Command Timeline combining commands and agent events](docs/images/command-timeline.png)

Filter commands and agent events by kind, failure state, session, and query. Markdown export supports metadata-only, redacted, and full-output modes.

### Settings and languages

![ApexTerm Settings for language, terminal, and transcript controls](docs/images/settings.png)

Change the application language, interface appearance, accent color, terminal behavior, transcript mode, sidebars, keybindings, UI controls, remote hosts, and the optional DevSpace companion from Settings.

### Compact tabs

![Compact ApexTerm window with icon-only separated tabs](docs/images/compact-tabs.png)

When space is limited, tab names automatically collapse into round icons while separators keep each tab visually distinct.

## Requirements

- macOS 14 or later
- Xcode command-line tools with Swift 6.2 support

## Build

```zsh
swift build --product ApexTerm
zsh scripts/build-app.zsh
```

The signed local application is written to `.artifacts/ApexTerm.app` by default.

## Regenerate README screenshots

```zsh
zsh scripts/capture-readme-screenshots.zsh
```

The script launches an isolated demo build, captures five deterministic feature scenes with ApexTerm's dark interface intact, and places each app view inside a rounded white presentation canvas. It writes the results to `docs/images/` without closing or modifying a normally running ApexTerm session.

## Optional DevSpace companion

ApexTerm works on its own. Developers who want ChatGPT to inspect and edit explicitly allowed local projects can optionally set up the public DevSpace fork:

- [uniplanck/devspace](https://github.com/uniplanck/devspace)

DevSpace is a separate self-hosted MCP server. It is not required for ApexTerm's terminal, tab, pane, history, shortcut, or tmux features. A setup link is also available inside **ApexTerm → Settings → DevSpace**.

## Security

- Do not commit API keys, cookies, private keys, `.env` files, or local authentication files.
- Grant DevSpace access only to project folders you intentionally expose.
- Review commands and repository changes before committing, pushing, or publishing.

## Development

The public `main` branch is the source of truth. Develop focused changes on feature branches, verify the affected build and E2E flow, and do not commit build products or local machine configuration.
