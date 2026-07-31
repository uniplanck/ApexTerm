# ApexTerm

ApexTerm is a native macOS terminal workspace focused on fast tab and pane navigation, command transcripts, tmux workflows, searchable history, and optional agent-assisted development.

> ApexTerm is under active development. Back up important terminal workflows before testing development builds.

## Highlights

- Native macOS terminal windows powered by SwiftTerm
- Tabs plus nested split panes
- Keyboard-configurable tab and pane navigation
- Command transcript modes, history search, and latest-output copy
- tmux session support and remote host profiles
- Compact title bar and small-window layouts
- Optional external agent-provider workflows

## Requirements

- macOS 14 or later
- Xcode command-line tools with Swift 6.2 support

## Build

```zsh
swift build --product ApexTerm
```

Build a signed local app bundle:

```zsh
zsh scripts/build-app.zsh
```

The resulting app is written to `.artifacts/ApexTerm.app` by default.

## Optional DevSpace companion

ApexTerm works on its own. Developers who want ChatGPT to inspect and edit explicitly allowed local projects can optionally set up the public DevSpace fork:

- [uniplanck/devspace](https://github.com/uniplanck/devspace)

DevSpace is a separate self-hosted MCP server. It connects ChatGPT to folders you explicitly allow; it is not required for ApexTerm's terminal, tab, pane, history, or tmux features.

A setup link is also available inside **ApexTerm → Settings → DevSpace**.

## Security

- Do not commit API keys, cookies, private keys, `.env` files, or local authentication files.
- DevSpace should only be granted access to project folders you intentionally expose.
- Review commands and repository changes before committing, pushing, or publishing.

## Development

The public `main` branch is the source of truth. Feature work should be developed on focused branches, tested, and merged without committing build products or local machine configuration.
