# ApexTerm

[English](../README.md) · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md) · **繁體中文** · [한국어](README.ko.md)

ApexTerm 是原生 macOS 終端工作區，整合分頁、分割窗格、命令紀錄、歷史搜尋、tmux、可自訂快捷鍵與選用的 Agent 輔助開發。

> ApexTerm 仍在積極開發中。測試開發版本前，請先保存重要的終端工作。

## 畫面與主要功能

![ApexTerm 分頁、三窗格工作區與命令紀錄](images/overview.png)

- 分頁與巢狀分割窗格
- 可自訂的分頁與窗格快捷鍵
- On / Off / Ex 命令紀錄模式
- 複製目前窗格的最新輸出並顯示完成提示
- 小視窗時自動切換為圓形圖示分頁
- tmux 工作階段與遠端主機設定

### 全域搜尋

![跨工作區、工作階段與命令的全域搜尋](images/universal-search.png)

按 `⌘K` 可搜尋 Workspace、Terminal Session、Command、Agent Chat 與 Agent Event。

### Command Timeline

![同時顯示命令與 Agent Event 的 Command Timeline](images/command-timeline.png)

可依類型、失敗狀態、工作階段與關鍵字篩選。Markdown 匯出支援僅中繼資料、遮罩與完整輸出。

### 設定與語言

![語言、終端與命令紀錄設定](images/settings.png)

可在 Settings 修改應用程式語言、介面外觀、強調色、終端行為、命令紀錄、側邊欄、快捷鍵、UI 控制項、遠端主機與選用的 DevSpace 說明。

### 精簡分頁

![小視窗中的圓形圖示分頁](images/compact-tabs.png)

空間不足時，分頁名稱會自動縮成圓形圖示，並保留分隔線以維持辨識度。

## 系統需求

- macOS 14 或更新版本
- 支援 Swift 6.2 的 Xcode Command Line Tools

## 建置

```zsh
swift build --product ApexTerm
zsh scripts/build-app.zsh
```

預設會將簽署後的本機應用程式產生於 `.artifacts/ApexTerm.app`。

## 重新產生 README 截圖

```zsh
zsh scripts/capture-readme-screenshots.zsh
```

腳本會啟動隔離的示範應用程式，保留 ApexTerm 的深色介面，並把五個功能場景放入圓角白色展示背景後輸出到 `docs/images/`。不會關閉或修改日常使用中的 ApexTerm 工作階段。

## 選用的 DevSpace 連接

ApexTerm 可以單獨使用。若希望透過 ChatGPT 查看與編輯明確授權的本機專案，可選擇安裝公開的 DevSpace fork：

- [uniplanck/devspace](https://github.com/uniplanck/devspace)

DevSpace 是另外自行託管的 MCP 伺服器，不是 ApexTerm 終端、分頁、窗格、歷史、快捷鍵或 tmux 功能的必要元件。

## 安全

請勿提交 API Key、Cookie、私鑰、`.env` 或本機驗證檔案。只授權 DevSpace 存取你明確想開放的專案資料夾。
