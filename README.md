# AriaFlow

<p align="center">
  <img src="docs/assets/AppIcon.png" alt="AriaFlow app icon" width="96">
</p>

[中文](#中文) | [English](#english)

<p align="center">
  <img src="docs/assets/AriaFlow.png" alt="AriaFlow main window" width="820">
</p>

## 中文

AriaFlow 是 macOS 原生 SwiftUI 下载客户端，使用本地随包的 `aria2-next` 引擎处理 HTTP/HTTPS、磁力链接、ED2K 和 Torrent 下载，也可以调用本机 `tdl` 直接下载 Telegram 消息中的视频或媒体。

### 功能

- 下载队列、开始/暂停、删除、在 Finder 中显示和复制链接。
- 直接粘贴 Telegram 消息链接，交给本机 `tdl` 下载；无需先在 Telegram 客户端缓存再另存，并实时显示进度、已下载大小、速度与剩余时间。
- 任务历史、搜索、状态筛选、菜单栏速度和 Dock 进度。
- 可配置保存位置、并发数、分片数、单服务器连接数和上下行限速。
- 可加载本地 BT Peer Blocklist，并在运行时重新加载或清除。
- 本地 JSON-RPC 引擎、Apple Silicon 与 Intel sidecar，以及离线本地设置。

### 系统要求

- macOS 14 或更高版本；macOS 26 会启用 Liquid Glass 效果。
- 源码构建需要 Xcode 26 或兼容的 Swift 6.2 工具链。
- Telegram 下载是可选功能，需要另外安装并登录 `tdl`。

### 启用 Telegram 下载

AriaFlow 不捆绑 `tdl`，会自动查找 Homebrew 安装路径。首次使用前执行：

```bash
brew install telegram-downloader
tdl login -T qr
```

登录完成后，在“新建任务 → Telegram”中粘贴一个或多个具体消息链接，例如 `https://t.me/channel/123`。AriaFlow 会顺序执行任务，支持暂停后通过 `tdl --continue` 断点续传，并自动下载同一相册中的媒体。新建任务时选择的完整目录会直接传给 `tdl`，并显示在任务行中。

### 下载与安装

从 [Releases](https://github.com/FateLightX/AriaFlow/releases) 下载 ZIP 和对应 `.sha256` 校验文件。当前开发版本使用 ad-hoc 签名，未经过 Apple 公证。首次打开时，Gatekeeper 可能拦截应用：在 Finder 中按住 Control 点击 `AriaFlow.app`，选择“打开”，然后再次确认。

### 构建与验证

```bash
swift build --disable-sandbox
scripts/package_app.sh
scripts/verify_release.sh
```

构建产物位于 `dist/AriaFlow.app`、`dist/AriaFlow-<version>.zip` 和校验文件。更多 sidecar 安装和校验说明见 [docs/SIDECAR.md](docs/SIDECAR.md)。

### 贡献与反馈

提交 Bug 或功能建议前，请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。不要在 issue、日志或截图中包含私有下载地址、凭据或 RPC Secret。安全问题请遵循 [SECURITY.md](SECURITY.md)。

## English

AriaFlow is a native SwiftUI download client for macOS. It runs a bundled local `aria2-next` engine for HTTP/HTTPS, magnet, ED2K, and torrent downloads, and can invoke a local `tdl` installation to download videos or media directly from Telegram messages.

### Highlights

- Download queue with start, pause, delete, Reveal in Finder, and copy-link actions.
- Paste Telegram message links and download them through local `tdl`, without first caching the media in the Telegram client, while viewing live progress, downloaded size, speed, and ETA.
- Task history, search, status filters, menu bar speed, and Dock progress.
- Configurable save location, concurrency, split count, per-server connections, and transfer limits.
- Local BT peer blocklist loading with runtime reload and clearing.
- Local JSON-RPC engine with Apple Silicon and Intel sidecars; no account or cloud service is required.

### Requirements

- macOS 14 or later; Liquid Glass styling is enabled on macOS 26.
- Xcode 26 or a compatible Swift 6.2 toolchain to build from source.
- Telegram downloads are optional and require a separate `tdl` installation and login.

### Enable Telegram downloads

AriaFlow does not bundle `tdl`; it discovers common Homebrew paths automatically. Run this once before using the Telegram tab:

```bash
brew install telegram-downloader
tdl login -T qr
```

Then open **New Task → Telegram** and paste one or more concrete message links such as `https://t.me/channel/123`. AriaFlow runs Telegram jobs sequentially, resumes interrupted jobs with `tdl --continue`, and includes media from grouped messages. The directory selected in the new-task sheet is passed directly to `tdl` and shown on the task row.

### Download and install

Download the ZIP and matching `.sha256` file from [Releases](https://github.com/FateLightX/AriaFlow/releases). Current developer builds are ad-hoc signed and are not notarized. Gatekeeper may block the first launch; Control-click `AriaFlow.app` in Finder, choose **Open**, then confirm.

### Build and verify

```bash
swift build --disable-sandbox
scripts/package_app.sh
scripts/verify_release.sh
```

Artifacts are written to `dist/AriaFlow.app`, `dist/AriaFlow-<version>.zip`, and its checksum. See [docs/SIDECAR.md](docs/SIDECAR.md) for bundled-engine installation and verification.

### Contributing and support

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. Remove private download URLs, credentials, and RPC Secrets from reports. Follow [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Development Docs

- [AI / agent recovery context](AGENTS.md)
- [Architecture and module boundaries](docs/ARCHITECTURE.md)
- [Sidecar replacement and runtime contract](docs/SIDECAR.md)
- [Release verification](docs/RELEASE_CHECKLIST.md)

## 致谢 / Acknowledgements

Thanks to [AnInsomniacy/aria2-next](https://github.com/AnInsomniacy/aria2-next), [AnInsomniacy/motrix-next](https://github.com/AnInsomniacy/motrix-next), and [iyear/tdl](https://github.com/iyear/tdl).

## Licensing

AriaFlow source code is available under the [MIT License](LICENSE). Bundled `aria2-next` engines are separate GPL-2.0 components; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [docs/SIDECAR.md](docs/SIDECAR.md) for their source, checksums, and redistribution details. `tdl` is an optional external AGPL-3.0 tool and is not redistributed with AriaFlow.
