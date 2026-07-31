# ApexTerm

[English](../README.md) · [日本語](README.ja.md) · **简体中文** · [繁體中文](README.zh-Hant.md) · [한국어](README.ko.md)

ApexTerm 是一个原生 macOS 终端工作区，集成了标签页、分割窗格、命令记录、历史搜索、tmux、可配置快捷键和可选的 Agent 辅助开发。

> ApexTerm 仍在积极开发中。测试开发版本前，请保存重要的终端工作。

## 界面与主要功能

![ApexTerm 标签页、三窗格工作区和命令记录](images/overview.png)

- 标签页与嵌套分割窗格
- 可配置的标签页和窗格快捷键
- On / Off / Ex 命令记录模式
- 复制当前窗格的最新输出并显示完成提示
- 小窗口下自动切换为圆形图标标签
- tmux 会话与远程主机配置

### 全局搜索

![跨工作区、会话和命令的全局搜索](images/universal-search.png)

按 `⌘K` 可搜索工作区、终端会话、命令、Agent Chat 和 Agent Event。

### Command Timeline

![同时显示命令和 Agent Event 的 Command Timeline](images/command-timeline.png)

可按类型、失败状态、会话和关键词筛选。Markdown 导出支持仅元数据、脱敏和完整输出三种模式。

### 设置与语言

![语言、终端与命令记录设置](images/settings.png)

可在 Settings 中修改应用语言、界面外观、强调色、终端行为、命令记录、侧边栏、快捷键、UI 控件、远程主机和可选 DevSpace 说明。

### 紧凑标签页

![小窗口中的圆形图标标签页](images/compact-tabs.png)

空间不足时，标签名称会自动折叠为圆形图标，并保留分隔线以便识别。

## 系统要求

- macOS 14 或更高版本
- 支持 Swift 6.2 的 Xcode Command Line Tools

## 构建

```zsh
swift build --product ApexTerm
zsh scripts/build-app.zsh
```

默认会将签名后的本地应用生成到 `.artifacts/ApexTerm.app`。

## 重新生成 README 截图

```zsh
zsh scripts/capture-readme-screenshots.zsh
```

脚本会启动隔离的演示应用，在保留 ApexTerm 深色界面的同时，将五个功能场景放入圆角白色展示背景并写入 `docs/images/`。不会关闭或修改日常使用中的 ApexTerm 会话。

## 可选 DevSpace 连接

ApexTerm 可以独立使用。希望通过 ChatGPT 查看和编辑明确授权的本地项目时，可以选择安装公开的 DevSpace fork：

- [uniplanck/devspace](https://github.com/uniplanck/devspace)

DevSpace 是单独自托管的 MCP 服务器，不是 ApexTerm 的终端、标签页、窗格、历史记录、快捷键或 tmux 功能的必需组件。

## 安全

不要提交 API Key、Cookie、私钥、`.env` 或本地认证文件。只向 DevSpace 授权你明确希望开放的项目目录。
