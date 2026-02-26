# Privacy Policy / 私隱政策

---

## English

### Introduction

Gongje ("the App") is a macOS application that provides on-device Cantonese speech-to-text transcription. This privacy policy explains how the App handles your information.

The core principle is simple: **Gongje does not collect, store, or transmit any personal data.**

### Information We Do Not Collect

The App does not collect:

- Personal information (name, email, phone number, etc.)
- Usage analytics or telemetry
- Crash reports
- Advertising identifiers
- Location data

The App contains no analytics SDKs, no advertising frameworks, and no crash reporting services.

### Audio Data

The App uses your Mac's microphone to capture speech for transcription. Audio is:

- Processed entirely on your device using local machine learning models
- Used only in real-time for transcription
- Never recorded, saved, or transmitted to any server

Once transcription is complete, the audio data is immediately discarded.

### Network Usage

The App connects to the internet solely to download machine learning models from HuggingFace (huggingface.co). No user data, audio, transcription results, or usage information is ever sent over the network.

After models are downloaded, the App operates fully offline.

### Local Storage

The App stores the following data locally on your Mac:

- **Application preferences** (e.g., selected model, hotkey configuration, display settings) via macOS UserDefaults
- **Machine learning models** in `~/Documents/gongje/huggingface/`

This data never leaves your device.

### Permissions

The App requests two macOS permissions:

- **Microphone** — Required to capture your voice for speech-to-text transcription
- **Accessibility** — Required to type the transcribed text into your currently focused application

These permissions are used solely for their stated purposes.

### Third-Party Services

The App uses the following open-source libraries, none of which collect user data:

- **WhisperKit** — On-device speech recognition
- **MLX Swift** — On-device language model inference
- **KeyboardShortcuts** — Global hotkey registration

### Children's Privacy

The App does not collect any data from anyone, including children under the age of 13.

### Changes to This Policy

We may update this privacy policy from time to time. Changes will be posted in the project's GitHub repository.

### Contact

If you have questions about this privacy policy, please open an issue at:
https://github.com/hyperkit/gongje/issues

---

## 繁體中文

### 簡介

講嘢（「本應用程式」）是一款 macOS 應用程式，提供裝置端粵語語音轉文字功能。本私隱政策說明本應用程式如何處理您的資料。

核心原則非常簡單：**講嘢不會收集、儲存或傳輸任何個人資料。**

### 我們不收集的資料

本應用程式不會收集：

- 個人資料（姓名、電郵、電話號碼等）
- 使用分析或遙測數據
- 當機報告
- 廣告識別碼
- 位置資料

本應用程式不包含任何分析 SDK、廣告框架或當機報告服務。

### 音訊資料

本應用程式使用 Mac 的麥克風擷取語音以進行轉錄。音訊資料：

- 完全在您的裝置上使用本機機器學習模型處理
- 僅用於即時語音轉錄
- 絕不會被錄製、儲存或傳輸至任何伺服器

轉錄完成後，音訊資料會立即被丟棄。

### 網絡使用

本應用程式連接互聯網的唯一目的是從 HuggingFace (huggingface.co) 下載機器學習模型。任何用戶資料、音訊、轉錄結果或使用資訊均不會透過網絡傳送。

模型下載完成後，本應用程式可完全離線運作。

### 本機儲存

本應用程式在您的 Mac 上本機儲存以下資料：

- **應用程式偏好設定**（例如已選模型、快捷鍵設定、顯示設定）透過 macOS UserDefaults 儲存
- **機器學習模型**儲存於 `~/Documents/gongje/huggingface/`

這些資料絕不會離開您的裝置。

### 權限

本應用程式請求兩項 macOS 權限：

- **麥克風** — 用於擷取語音以進行語音轉文字
- **輔助使用** — 用於將轉錄文字輸入至您當前使用的應用程式

這些權限僅用於其所述用途。

### 第三方服務

本應用程式使用以下開源程式庫，均不會收集用戶資料：

- **WhisperKit** — 裝置端語音辨識
- **MLX Swift** — 裝置端語言模型推論
- **KeyboardShortcuts** — 全域快捷鍵註冊

### 兒童私隱

本應用程式不會收集任何人的資料，包括 13 歲以下的兒童。

### 政策變更

我們可能會不時更新本私隱政策。變更將發佈於本專案的 GitHub 儲存庫。

### 聯絡方式

如您對本私隱政策有任何疑問，請於以下連結提交問題：
https://github.com/hyperkit/gongje/issues
