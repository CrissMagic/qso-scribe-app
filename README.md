# 通联随记 / QSO Scribe App

中文 | [English](#english)

通联随记是一个面向业余无线电用户的移动端 QSO 记录助手。项目目标是让操作者在户外、移动或手持设备不便输入的场景中，尽量通过语音和 AI 辅助完成通联记录，而不是在通联过程中频繁手写或打字。

本项目参考了 [QSO Scribe](https://github.com/richcannings/qso-scribe) 的核心方向：用语音转写和 AI 结构化，把真实通联音频整理为可导出的日志。不同之处在于，本项目直接面向移动 App 产品化，首版优先 Android，并提供简体中文和英文界面。

## 为什么需要它

便携通联、POTA/SOTA 活动、野外架台或移动操作时，操作者通常要同时处理电台、话筒、天线、手机、纸笔和日志软件。通联过程中最容易出错的字段往往又是最关键的字段：呼号、频率/波段、模式、RST、时间。

通联随记希望把记录负担降下来：

- 通联时由用户手动开始和结束一条 QSO。
- App 采集音频或接收补录内容。
- 语音转写和结构化逻辑提取呼号、RST、波段、模式等字段。
- 用户复核并补全低置信度字段。
- 最终导出 ADIF、CSV 或原始转写文本。

## 当前 MVP 范围

当前版本聚焦本地优先的移动端 MVP。真实大模型和实时流式供应商的完整接入仍按后续集成推进，现阶段已保留供应商配置、模型分配和 OpenAI-compatible HTTP 接入边界。

已覆盖或已预留的能力包括：

- Android-first Flutter App。
- 简体中文和英文双语界面。
- 手动开始/结束 QSO。
- 实时流式转写与结束后统一识别两种模式配置。
- 录音采集、音频文件导入、纯文本导入。
- QSO 草稿复核和字段编辑。
- 必填字段校验：呼号、日期时间、频率或波段、模式、发送 RST、接收 RST。
- 扩展字段：姓名、QTH、备注、设备、天线。
- 日志状态：草稿、待确认、已确认、已导出、失败。
- 本地 SQLite 存储。
- 原始音频和原始转写保留策略。
- 供应商配置与模型分配分离。
- 按模型能力过滤转录、实时流式和结构化模型。
- ADIF、CSV、原始转写文本导出。
- 按状态、日期、波段、模式筛选导出。
- GitHub Release 更新检查、APK 下载进度和用户确认安装。

## 技术栈

- Flutter
- Riverpod
- SQLite / sqflite
- record
- file_picker
- OpenAI-compatible HTTP provider boundary

## 本地开发

### 环境要求

- Flutter SDK
- Android Studio 或可用的 Android SDK/JDK
- Android 模拟器或 Android 真机

### 安装依赖

```bash
flutter pub get
```

### 生成本地化代码

```bash
flutter gen-l10n
```

### 运行检查

```bash
flutter analyze
flutter test
```

### 启动 App

```bash
flutter run
```

### 构建 Android Debug APK

```bash
flutter build apk --debug --target-platform android-arm64
```

### 发布 Android Release APK

正式发布通过 GitHub Actions 完成。推送 tag 会触发 `.github/workflows/release.yml`，流水线会运行 `flutter analyze`、`flutter test`，再构建签名 APK 并上传到 GitHub Release。

发布 tag 必须和 `pubspec.yaml` 的 `version` 完全一致，格式为：

```text
v<major>.<minor>.<patch>+<build-number>
```

例如 `pubspec.yaml` 中为 `version: 0.1.2+3` 时，应推送 tag：

```bash
git tag v0.1.2+3
git push origin main
git push origin v0.1.2+3
```

GitHub Release 资产会使用 `qso-scribe-app-<version>-build<build-number>-android.apk` 命名，例如 `qso-scribe-app-0.1.2-build3-android.apk`。应用内更新检查会识别并下载该 APK。

## 项目结构

```text
lib/
  main.dart
  l10n/                     本地化资源和生成代码
  src/
    data/                   SQLite、Repository、导出服务
    domain/                 领域模型和过滤逻辑
    services/               录音、转写、结构化、模型列表服务
    state/                  Riverpod 状态和依赖注入
    ui/                     页面、主题和 App Shell
test/                       单元测试和 Widget 测试
android/                    Android 工程
req.md                      需求说明和 Roadmap
```

## 许可证

本项目使用 Apache License 2.0。详见 [LICENSE](./LICENSE)。

---

## English

[中文](#通联随记--qso-scribe-app) | English

QSO Scribe App is a mobile QSO logging assistant for amateur radio operators. Its goal is to reduce manual logging during portable, mobile, or field operations by using audio capture, speech transcription, and AI-assisted structuring.

The project is inspired by [QSO Scribe](https://github.com/richcannings/qso-scribe), which explores turning real activation audio into structured logs. This app focuses on productizing that idea as a mobile-first experience, starting with Android and supporting both Simplified Chinese and English.

## Why This Exists

During portable radio, POTA/SOTA-style activations, field setups, or mobile operation, the operator may be managing a radio, microphone, antenna, phone, paper log, and logging software at the same time. The fields that are easiest to miss are often the most important ones: callsign, band/frequency, mode, RST, and time.

QSO Scribe App aims to reduce that friction:

- The operator manually starts and ends each QSO.
- The app captures audio or accepts later imports.
- Speech transcription and structuring logic extracts callsigns, RST reports, bands, modes, and related fields.
- The operator reviews low-confidence fields and fills missing values.
- Logs can be exported as ADIF, CSV, or raw transcript text.

## Current MVP Scope

The current version focuses on a local-first mobile MVP. Full real-time provider integration and production-grade LLM/STT adapters are still integration work. The app already keeps the provider configuration, model assignment, and OpenAI-compatible HTTP boundary in place.

Covered or reserved capabilities include:

- Android-first Flutter app.
- Simplified Chinese and English UI.
- Manual QSO start/end.
- Configurable real-time streaming and post-QSO recognition modes.
- Audio recording, audio file import, and text import.
- QSO draft review and field editing.
- Required-field validation: callsign, date/time, frequency or band, mode, sent RST, received RST.
- Optional fields: name, QTH, notes, rig, antenna.
- Log statuses: draft, needs review, confirmed, exported, failed.
- Local SQLite storage.
- Raw audio and raw transcript retention policies.
- Separate provider configuration and model assignment.
- Capability-based filtering for transcription, streaming, and structuring models.
- ADIF, CSV, and raw transcript export.
- Export filtering by status, date, band, and mode.
- GitHub Release update checks, APK download progress, and user-confirmed install prompt.

## Tech Stack

- Flutter
- Riverpod
- SQLite / sqflite
- record
- file_picker
- OpenAI-compatible HTTP provider boundary

## Local Development

### Requirements

- Flutter SDK
- Android Studio or a working Android SDK/JDK
- Android emulator or physical Android device

### Install Dependencies

```bash
flutter pub get
```

### Generate Localizations

```bash
flutter gen-l10n
```

### Run Checks

```bash
flutter analyze
flutter test
```

### Run The App

```bash
flutter run
```

### Build Android Debug APK

```bash
flutter build apk --debug --target-platform android-arm64
```

### Publish Android Release APK

Production releases are built by GitHub Actions. Pushing a tag triggers `.github/workflows/release.yml`; the workflow runs `flutter analyze`, `flutter test`, builds the signed APK, and uploads it to GitHub Releases.

The release tag must exactly match `pubspec.yaml` `version` and use this format:

```text
v<major>.<minor>.<patch>+<build-number>
```

For example, when `pubspec.yaml` contains `version: 0.1.2+3`, push:

```bash
git tag v0.1.2+3
git push origin main
git push origin v0.1.2+3
```

The GitHub Release asset is named `qso-scribe-app-<version>-build<build-number>-android.apk`, for example `qso-scribe-app-0.1.2-build3-android.apk`. The in-app updater detects and downloads that APK.

## Project Structure

```text
lib/
  main.dart
  l10n/                     localization resources and generated code
  src/
    data/                   SQLite, repositories, export services
    domain/                 domain models and filtering logic
    services/               recording, transcription, structuring, model fetch services
    state/                  Riverpod state and dependency injection
    ui/                     screens, theme, and app shell
test/                       unit and widget tests
android/                    Android project
req.md                      requirements and roadmap
```

## License

This project is licensed under the Apache License 2.0. See [LICENSE](./LICENSE).
