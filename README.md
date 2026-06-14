# Sign Language Translator

A real-time sign language translation app built with Flutter. Keypoint extraction and word recognition run **entirely on-device** — no camera data ever leaves the phone. An optional backend (Ollama/Qwen2.5) is used only to form a fluent sentence from the recognized word list.

Supports **Turkish Sign Language** (TİD / AUTSL, 226 classes) and **American Sign Language** (ASL Citizen, 20 classes).

---

## Features

- **On-device keypoint extraction** — native MediaPipe HolisticLandmarker (iOS: Swift, Android: Kotlin) converts each camera frame into a 1692-dimensional keypoint vector (pose × 132 + face × 1434 + left hand × 63 + right hand × 63)
- **On-device word recognition** — INT8 dynamically-quantized ONNX model runs over 30-frame sliding windows; motion and hand-presence gates reduce false positives; a momentum filter prevents noisy single-frame predictions
- **Skeleton overlay** — body pose and hand landmarks are drawn live on the camera preview
- **Dual model support** — switch between TR (AUTSL) and EN (ASL Citizen) models from the camera screen
- **Sentence generation** — after 3 seconds of silence, recognized words are sent to an Ollama/Qwen2.5 backend to form a natural sentence (falls back to joining words with spaces if backend is unreachable)
- **Translation history** — all completed sentences are saved locally and browsable with search and pull-to-refresh
- **Dark / light mode** — toggle in Settings; preference is persisted across sessions
- **Bilingual UI** — full Turkish / English localization across all screens and navigation
- **Copy to clipboard** — one-tap copy of any completed translation
- **Privacy policy** — all processing is on-device; no video or personal data is transmitted

---

## Screenshots

| Camera | History | Settings (Dark) | Settings (Light) |
|--------|---------|-----------------|------------------|
| Real-time skeleton overlay, word chips, sentence panel | Searchable translation log | Dark mode with appearance toggle | Light mode |

---

## How It Works

```
Camera frame  (100 ms interval, JPEG → base64)
      │
      ▼
Native MediaPipe HolisticLandmarker
(iOS Swift plugin / Android Kotlin plugin)
      │   → 1692-dim keypoint vector
      ▼
30-frame sliding buffer
      │
      ├── Gate 1: hand present in ≥ 50% of recent frames?
      ├── Gate 2: sufficient motion between frames?
      ▼
ONNX Runtime  (on-device)
AUTSL model (TR) or ASL Citizen model (EN)
      │   → word label + confidence score
      ├── Momentum filter: same word confirmed N times?
      ▼
Word list
      │
      └── 3 s silence →  POST /sentence
                          Ollama / Qwen2.5 (backend, optional)
                               │
                               ▼
                          Fluent sentence displayed
```

---

## Project Structure

```
Capstone4992/
├── lib/
│   ├── main.dart                           # Entry point, Provider setup
│   ├── screens/
│   │   ├── camera_screen.dart              # Live recognition screen
│   │   ├── history_screen.dart             # Translation history
│   │   └── settings_screen.dart           # Appearance / privacy settings
│   ├── services/
│   │   ├── api_service.dart                # HTTP client for /sentence endpoint
│   │   ├── camera_service.dart             # Camera lifecycle management
│   │   ├── mediapipe_channel_service.dart  # Flutter ↔ native MediaPipe bridge
│   │   ├── on_device_sign_service.dart     # Gate + momentum pipeline
│   │   ├── sign_recognizer_service.dart    # ONNX Runtime inference wrapper
│   │   ├── history_service.dart            # SharedPreferences persistence
│   │   ├── language_notifier.dart          # UI language state (TR / EN)
│   │   └── theme_notifier.dart             # Dark / light theme state
│   ├── models/
│   │   └── translation_entry.dart          # History record model (JSON-serializable)
│   ├── widgets/
│   │   ├── bottom_nav.dart                 # Localized bottom navigation bar
│   │   └── type_badge.dart                 # Language badge chip (TSİD / TİD)
│   └── theme/
│       └── app_theme.dart                  # AppColors, AppColorSet, AppTheme
├── assets/
│   └── models/                             # ONNX models + preprocessing metadata
├── ios/
│   └── Runner/MediaPipePlugin.swift        # iOS native HolisticLandmarker plugin
├── android/
│   └── app/src/main/kotlin/.../
│       ├── MainActivity.kt                 # Registers MediaPipePlugin
│       └── MediaPipePlugin.kt              # Android native HolisticLandmarker plugin
├── pubspec.yaml
└── analysis_options.yaml
```

---

## Getting Started

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | `>= 3.0.0` |
| Dart | `>= 3.0.0` |
| Xcode | `>= 14` (iOS builds) |
| Android Studio / SDK | API 24+ (Android builds) |
| CocoaPods | latest (iOS dependency manager) |

### 1. Clone & install dependencies

```bash
git clone https://github.com/alikaanozdemir/Capstone4992.git
cd Capstone4992
flutter pub get
```

### 2. iOS setup

```bash
cd ios
pod install
cd ..
flutter run -d <your-ios-device-or-simulator>
```

> **Note:** The app requires camera permission. Accept the permission prompt on first launch. Physical device is recommended — the iOS simulator does not support camera.

### 3. Android setup

```bash
flutter run -d <your-android-device-or-emulator>
```

> **Note:** Minimum SDK is API 24 (Android 7.0). MediaPipe and ONNX Runtime are included via Gradle — no manual native setup needed.

### 4. Build a release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk  (~110 MB)
```

Or download the latest pre-built APK from [GitHub Releases](https://github.com/alikaanozdemir/Capstone4992/releases).

---

## Backend Setup (Optional)

The backend is **not required** for sign language recognition — keypoint extraction and ONNX inference run fully on-device. The backend is only used to form a grammatically natural sentence from the detected word list.

The default URL is `http://10.0.2.2:8000` (Android emulator localhost). To change it, update `_defaultUrl` in `lib/services/api_service.dart`.

Refer to the `capstone_final/` directory for backend setup instructions (Ollama + Qwen2.5).

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `camera` | Camera stream and frame capture |
| `onnxruntime` | On-device ONNX model inference |
| `http` | REST communication with sentence-generation backend |
| `shared_preferences` | Persistent settings and history storage |
| `provider` | State management (ThemeNotifier, LanguageNotifier) |
| `google_fonts` | DM Sans typography |
| `permission_handler` | Camera permission management |

**Native (outside pubspec):**
- iOS: `MediaPipeTasksVision` via CocoaPods
- Android: `com.google.mediapipe:tasks-vision:0.10.14` via Gradle
- Both platforms use the `holistic_landmarker.task` model file bundled in app assets

---

## Privacy

All sign language recognition is performed locally on the device. No video, images, or biometric data are transmitted to any server. Translation history is stored only on the device and can be deleted at any time from **Settings → Privacy → Clear history**.

---

## License

This project was developed as a capstone project. All rights reserved.
