# Code Ground Truth — Capstone4992 (Sign App)

**This document is a read-only, fact-based snapshot of the actual code.** No code was modified to produce this file. Every claim below is tied to a concrete file path and, where applicable, a class/method name and line number. Where the code does not make something verifiable, the item is marked **"uncertain"** rather than guessed.

## 0. Scope

- **Branch analyzed:** `feature/live-camera-stream`
- **HEAD commit:** `d4a6523b109ad61716ba315d3f72021446a42447` ("Run HolisticLandmarker on GPU delegate to cut MediaPipe latency"), 2 commits ahead of `origin/feature/live-camera-stream`
- **Working tree state at analysis time:** the committed HEAD plus the following **uncommitted** changes (from `git status --porcelain`), which are included in this analysis because they reflect the current functional state of the app:
  - Modified: `lib/main.dart`, `lib/screens/camera_screen.dart`, `lib/screens/settings_screen.dart`, `lib/services/on_device_sign_service.dart`, `lib/services/sign_recognizer_service.dart`, `pubspec.yaml`, `pubspec.lock`, `android/gradle.properties`, `ios/Podfile.lock`, `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`, `macos/Flutter/GeneratedPluginRegistrant.swift`
  - Deleted: `lib/services/api_service.dart`
  - New (untracked): `lib/widgets/disclaimer_dialog.dart`

### `main` vs `feature/live-camera-stream` — architectural difference

`git diff main...feature/live-camera-stream --stat` (committed history only, before the uncommitted changes above) reports **40 files changed, 1406 insertions(+), 821 deletions(-)**. The two branches represent **two different architectures**:

- **`main`** = the architecture the current report describes: `lib/services/api_service.dart` exists and POSTs to `$_baseUrl/sentence` (default `http://10.0.2.2:8000`, configurable via `shared_preferences` key `backend_url`); `lib/screens/camera_screen.dart` uses `Timer.periodic(const Duration(milliseconds: 100), ...)` → `_cam.takePicture()` → `base64Encode(bytes)` → `_onDevice.processFrame(b64)` (verified via `git show main:lib/screens/camera_screen.dart`, lines 112-118, 121-127).
- **`feature/live-camera-stream`** (this branch, working tree) = a fully on-device, raw-frame-stream pipeline (`startImageStream`, native MediaPipe, on-device ONNX, no network calls at all — see Sections B-I below).

The current report's Abstract/technical sections describe the **`main`-branch-era architecture**, which no longer matches `feature/live-camera-stream`.

---

## A. Dependencies & Tech Stack

1. **Direct Flutter dependencies** (`pubspec.yaml:10-22`, resolved versions from `pubspec.lock`):

   | Package | Constraint (`pubspec.yaml`) | Resolved (`pubspec.lock`) |
   |---|---|---|
   | `cupertino_icons` | `^1.0.6` | `1.0.9` |
   | `google_fonts` | `^6.1.0` | `6.3.3` |
   | `flutter_animate` | `^4.5.0` | `4.5.2` |
   | `go_router` | `^13.2.0` | `13.2.5` |
   | `provider` | `^6.1.2` | `6.1.5+1` |
   | `camera` | `^0.10.5+9` | `0.10.6` |
   | `permission_handler` | `^11.3.0` | `11.4.0` |
   | `shared_preferences` | `^2.2.3` | `2.5.5` |
   | `onnxruntime` | `^1.4.0` | `1.4.1` |
   | `flutter_tts` | `^4.2.5` | `4.2.5` |

   Dev dependencies (`pubspec.yaml:24-27`): `flutter_test` (sdk), `flutter_lints ^3.0.0`.

2. **`http` package**: present in `pubspec.lock` as `dependency: transitive`, resolved version `1.6.0` — **not** a direct dependency anymore (it was removed from `pubspec.yaml` dependencies in this session's uncommitted change). A repo-wide `grep -rn "http"` over `lib/` returns **zero matches** (see Section G item 4).

3. **ONNX Runtime package name/version — confirmed exact**: `onnxruntime: ^1.4.1` resolved (`pubspec.lock`), imported in code as `package:onnxruntime/onnxruntime.dart` (`lib/services/sign_recognizer_service.dart:6`). The package is named **`onnxruntime`**, NOT `onnxruntime_v2`.

4. **Native ONNX Runtime version bundled by the `onnxruntime` Flutter plugin v1.4.1**:
   - iOS: `ios/Podfile.lock` lines 8-15 — `onnxruntime (0.0.1)` depends on `onnxruntime-objc (= 1.15.1)`, which depends on `onnxruntime-c (= 1.15.1)`.
   - Android: bundled native libraries at `~/.pub-cache/hosted/pub.dev/onnxruntime-1.4.1/android/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/libonnxruntime.so`; `strings` on the `arm64-v8a` binary yields version string `1.15.1`.
   - **Conclusion**: native ONNX Runtime is **1.15.1** on both platforms (consistent).

5. **MediaPipe Tasks Vision version — iOS**: `ios/Podfile.lock` lines 5-7 — `MediaPipeTasksVision (0.10.35)` depends on `MediaPipeTasksCommon (= 0.10.35)`.

6. **MediaPipe Tasks Vision version — Android**: `android/app/build.gradle.kts:44` — `implementation("com.google.mediapipe:tasks-vision:0.10.14")`.

   ⚠️ **iOS (0.10.35) and Android (0.10.14) use different MediaPipe Tasks Vision versions** — see Section J item 1.

7. **Gradle / AGP / Kotlin / Java versions (from `android/`)**:
   - Gradle: `android/gradle/wrapper/gradle-wrapper.properties:5` → `distributionUrl=...gradle-8.14-all.zip` → **Gradle 8.14**.
   - Android Gradle Plugin: `android/settings.gradle.kts:22` → `id("com.android.application") version "8.11.1"` → **AGP 8.11.1**.
   - Kotlin: `android/settings.gradle.kts:23` → `id("org.jetbrains.kotlin.android") version "2.2.20"` → **Kotlin 2.2.20**.
   - Java/Kotlin compile target: `android/app/build.gradle.kts:14-15,19` → `JavaVersion.VERSION_17` (both `sourceCompatibility`/`targetCompatibility` and `kotlinOptions.jvmTarget`).
   - `compileSdk` (`android/app/build.gradle.kts:10`) and `targetSdk` (`:25`) are set to `flutter.compileSdkVersion` / `flutter.targetSdkVersion` — i.e. **resolved by the installed Flutter SDK, not hardcoded** in this repo. `minSdk` is hardcoded: `android/app/build.gradle.kts:24` → `minSdk = 24`.
   - Release build type (`android/app/build.gradle.kts:31-35`): uses the **debug** signing config, `isMinifyEnabled = true`, with `proguard-rules.pro`.

---

## B. End-to-end pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│ CameraService.initialize()/startImageStream()                            │
│ lib/services/camera_service.dart:14-36                                   │
│   ResolutionPreset.low; imageFormatGroup = yuv420 (Android) / bgra8888   │
│   (iOS); _controller!.startImageStream(onFrame)                          │
└───────────────────────────────┬───────────────────────────────────────────┘
                                  │ CameraImage (per native-frame callback)
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ _CameraScreenState._onCameraImage(image)                                  │
│ lib/screens/camera_screen.dart:116-120                                    │
│   if (_capturing || !_camReady || !_onDeviceReady) return;  ← frame drop │
│   _capturing = true; _processImage(image).whenComplete(()=>_capturing=false)│
└───────────────────────────────┬───────────────────────────────────────────┘
                                  │ CameraFrame (_toCameraFrame, :122-131)
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ OnDeviceSignService.processFrame(frame)                                   │
│ lib/services/on_device_sign_service.dart:131-241                         │
│                                                                            │
│  1. MediaPipeChannelService.extractKeypoints(frame)                      │
│     lib/services/mediapipe_channel_service.dart:46-65                    │
│       → MethodChannel('sign.language.mediapipe')                        │
│          ├ iOS:     ios/Runner/MediaPipePlugin.swift                     │
│          └ Android: android/.../MediaPipePlugin.kt                      │
│       → HolisticLandmarker.detect() (GPU delegate)                       │
│       → 1692-dim Float vector: pose(132)+face(1434)+lh(63)+rh(63)        │
│                                                                            │
│  2. _kpBuf.add(kp); cap at 30 frames (:153-154, _bufSize=30)             │
│                                                                            │
│  3. Gate 1 — hand presence over last 15 frames, ratio ≥ 0.5 (:165-176)   │
│     Gate 2 — motion variance over hand coords > 0.003² (:178-187)        │
│                                                                            │
│  4. SignRecognizerService.predict(_kpBuf)                                │
│     lib/services/sign_recognizer_service.dart:143-189                    │
│       _perSeqCenter (:82-114) → _standardize w/ feat_mean/feat_std       │
│       (:117-129) → Float32List [1,30,1692]                               │
│       → OrtSession.runAsync({'keypoints': tensor}) → 'logits' [1,N]      │
│       → _softmax (:131-136) → argmax (:183-186) → (label, confidence)   │
│                                                                            │
│  5. confThresh 0.35 gate + momentum filter (momentum=2, _lastEmit)       │
│     (:211-240) → word (String?) or null                                  │
└───────────────────────────────┬───────────────────────────────────────────┘
                                  │ FrameResult{word, confidence, poseLm,
                                  │  lhLm, rhLm, mediapipeMs, inferenceMs}
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ _CameraScreenState._processImage (camera_screen.dart:133-167)            │
│   updates skeleton overlay, confidence badge, debug overlay;             │
│   if word != null → _words.add(word) (cap 6, :145-148) + _resetSilence() │
└───────────────────────────────┬───────────────────────────────────────────┘
                                  │ 3s silence timer (:60-61, 169-172)
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ _CameraScreenState._buildSentence (camera_screen.dart:184-202)           │
│   _composeSentence(words): join + capitalize + punctuation, pure Dart,  │
│   NO network call (:175-182)                                             │
│   HistoryService.add(...) → shared_preferences (:190-195)                │
│   setState(_sentence = ...)                                              │
└───────────────────────────────┬───────────────────────────────────────────┘
                                  │ user taps "Speak" / "Sesli Oku"
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ _CameraScreenState._speak (camera_screen.dart:205-210)                   │
│   FlutterTts().setLanguage('tr-TR'|'en-US') → .speak(_sentence)          │
│   (offline, on-device system TTS engine)                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## C. Camera capture

1. **Capture method**: `CameraController.startImageStream()` (`lib/services/camera_service.dart:35`), invoked from `_CameraScreenState._startCapture()` (`lib/screens/camera_screen.dart:109-111`). This is a **raw image stream**, NOT `takePicture()`/file-based capture. (The `main` branch used `Timer.periodic(Duration(milliseconds: 100)) → _cam.takePicture() → base64Encode` — see Section I.)

2. **`ResolutionPreset`**: `ResolutionPreset.low` (`lib/services/camera_service.dart:20`).

3. **`imageFormatGroup`**: `lib/services/camera_service.dart:22-24` — `ImageFormatGroup.yuv420` on Android, `ImageFormatGroup.bgra8888` on iOS (`Platform.isAndroid` check).

4. **Frame throttling/drop logic**: `_CameraScreenState._onCameraImage` (`lib/screens/camera_screen.dart:116-120`):
   ```dart
   void _onCameraImage(CameraImage image) {
     if (_capturing || !_camReady || !_onDeviceReady) return;
     _capturing = true;
     _processImage(image).whenComplete(() => _capturing = false);
   }
   ```
   `_capturing` is a `bool` field (`camera_screen.dart:50`). There is **no fixed-interval timer** — every frame the camera driver delivers is either processed (if the previous frame finished) or dropped (if `_capturing == true`). There is no separate FPS cap constant in this file beyond this busy-flag.

---

## D. Native MediaPipe keypoint extraction

1. **iOS HolisticLandmarker config** — `ios/Runner/MediaPipePlugin.swift:75-91` (`setupLandmarker()`):
   - `options.baseOptions.delegate = .GPU` → **`ios/Runner/MediaPipePlugin.swift:83`** — GPU delegate IS active.
   - `options.runningMode = .image` (`:84`).
   - Confidence thresholds, all `0.5`: `minFaceDetectionConfidence`, `minFacePresenceConfidence`, `minPoseDetectionConfidence`, `minHandLandmarksConfidence` (`:85-88`).

2. **Android HolisticLandmarker config** — `android/app/src/main/kotlin/com/example/sign_app/MediaPipePlugin.kt:61-81` (`initialize()`):
   - `.setDelegate(Delegate.GPU)` → **`MediaPipePlugin.kt:67`** — GPU delegate IS active.
   - `.setRunningMode(RunningMode.IMAGE)` (`:70`).
   - Same `0.5` confidence thresholds (`:71-74`).

3. **`.task` model bundled**:
   - iOS: `ios/Runner/holistic_landmarker.task` — **13,683,609 bytes** (~13.0 MB), referenced by `Bundle.main.path(forResource: "holistic_landmarker", ofType: "task")` (`MediaPipePlugin.swift:76`).
   - Android: `android/app/src/main/assets/holistic_landmarker.task` — **13,683,609 bytes**, referenced by `.setModelAssetPath("holistic_landmarker.task")` (`MediaPipePlugin.kt:66`).
   - Both files have identical MD5 (`dd9cb00e9d9933dac7988d8ce347ba7b`) — **same model file on both platforms**, only mtimes differ.

4. **1692-dim breakdown — verified directly from code on both platforms**:
   - Pose: 33 landmarks × 4 values (x, y, z, visibility) = **132** — `MediaPipePlugin.swift:18,167-176`; `MediaPipePlugin.kt:106-116`.
   - Face: 478 landmarks × 3 values (x, y, z) = **1434** — `MediaPipePlugin.swift:19,179-188`; `MediaPipePlugin.kt:118-127`.
   - Left hand: 21 landmarks × 3 values (x, y, z) = **63** — `MediaPipePlugin.swift:20,190-200`; `MediaPipePlugin.kt:129-138`.
   - Right hand: 21 landmarks × 3 values (x, y, z) = **63** — `MediaPipePlugin.swift:20,202-212`; `MediaPipePlugin.kt:140-149`.
   - Total: 132 + 1434 + 63 + 63 = **1692** (`MediaPipePlugin.swift:21` `totalDim = 1692`). Order in the flattened vector is exactly **pose → face → left hand → right hand**, matching `lib/services/on_device_sign_service.dart:84-85` (`_faceEnd = 132+1434 = 1566`, `_lhEnd = _faceEnd+63 = 1629`).

5. **Frame format passed to native / orientation handling**:
   - **iOS**: the single camera plane is BGRA8888 bytes (`camera_screen.dart` passes `image.planes[0].bytes` via `mediapipe_channel_service.dart:46-65`). `MediaPipePlugin.swift._extractKeypoints` builds a `CVPixelBuffer` of `kCVPixelFormatType_32BGRA` via `makePixelBuffer` (`:96-130`), then wraps it as `MPImage(pixelBuffer:orientation: .up)` (`:144-152`, "Option A": the comment states the BGRA camera stream already arrives upright, and `HolisticLandmarker` rejects any non-`.up` orientation with error code 3).
   - **Android**: 3-plane YUV420 bytes are converted to an ARGB_8888 `Bitmap` via `yuv420ToBitmap` (BT.601 limited-range integer conversion, `MediaPipePlugin.kt:156-193`), then rotated upright via `rotateBitmap(bitmap, rotationDegrees)` (`:196-200`) using the `rotation` value sent from Dart (`_toCameraFrame`, `camera_screen.dart:122-131`, derived from `_cam.sensorOrientation`), then wrapped with `BitmapImageBuilder(upright).build()` (`:95`).

---

## E. On-device ONNX inference

1. **Execution providers, order, file/method** — `lib/services/sign_recognizer_service.dart:60-77` (`_buildSessionOptions()`):
   ```dart
   if (Platform.isAndroid) {
     opts.appendNnapiProvider(NnapiFlags.useNone);    // :64
     _activeProvider = 'NNAPI';
   } else if (Platform.isIOS) {
     opts.appendCoreMLProvider(CoreMLFlags.useNone);  // :67
     _activeProvider = 'CoreML';
   }
   // ... try/catch fallback to 'CPU' on error
   try { opts.appendXnnpackProvider(); } catch (_) {}   // :74
   try { opts.appendCPUProvider(CPUFlags.useNone); } catch (_) {} // :75
   ```
   This is **manual** platform branching (`Platform.isAndroid`/`Platform.isIOS`), not `appendDefaultProviders()`. Order: NNAPI (Android) or CoreML (iOS) first, then XNNPACK, then CPU — both XNNPACK and CPU are always appended as fallbacks regardless of platform.

2. **Model files** (`assets/models/`, declared in `pubspec.yaml:33-36`):
   - `model_autsl.onnx` — **1,061,711 bytes** (~1.0 MB).
   - `model_asl_citizen.onnx` — **670,671 bytes** (~655 KB).
   - `preprocess_autsl.json` — **79,086 bytes**; `n_classes=226`, `seq_len=30`, `input_size=1692`, `labels` array length **226**, `feat_mean`/`feat_std` present (length 1692 each), `val_acc=0.8938053097345132`.
   - `preprocess_asl_citizen.json` — **77,285 bytes**; `n_classes=20`, `seq_len=30`, `input_size=1692`, `labels` array length **20**, `feat_mean`/`feat_std` present (length 1692 each), `val_acc=0.6818181818181818`.

3. **Input/output tensor names and shapes**:
   - Input tensor name **`keypoints`**, shape `[1, seqLen, featureDim]` = `[1, 30, 1692]` — created via `OrtValueTensor.createTensorWithDataList(flat, [1, seqLen, featureDim])` and passed as `{'keypoints': tensor}` (`sign_recognizer_service.dart:163,168`). Confirmed present as a string in both `.onnx` files (`strings` search → `keypoints`, `keypoints_QuantizeLinear`).
   - Output tensor name **`logits`** (confirmed via `strings` on both `.onnx` files), shape `[1, n_classes]`. Code reads `outputs[0]!.value as List<List<double>>` and takes `[0]` (`sign_recognizer_service.dart:176-180`).

4. **INT8 quantization — verified via op inspection**: `strings -a` on both `assets/models/model_autsl.onnx` and `assets/models/model_asl_citizen.onnx` shows the op types **`MatMulInteger`**, **`DynamicQuantizeLinear`**, and **`DynamicQuantizeLSTM`**, plus numerous `*_QuantizeLinear` tensor names (e.g. `keypoints_QuantizeLinear`, `.../transformer/layers.{0,1}/...QuantizeLinear`). This is **dynamic INT8 quantization**, consistent with `/Users/erimozer/Desktop/capstone/aimodel/real-time-sign-language-recognition-and-translation/convert_to_onnx.py:84`: `quantize_dynamic(fp32_path, onnx_path, weight_type=QuantType.QInt8)`. The export uses `opset_version=17` (`convert_to_onnx.py:73`) and downgrades `ir_version` to 9 if greater (`convert_to_onnx.py:94-95`). The node names also reveal a 2-layer Transformer-based architecture (`transformer/layers.0`, `transformer/layers.1`, `self_attn`, `LayerNormalization`, `classifier.0`).

5. **Preprocessing in Dart vs. Python training/reference code**:
   - **`_perSeqCenter`** (`sign_recognizer_service.dart:82-114`): for frames whose `sum(abs(feature)) > 1e-6`, subtract the per-feature mean computed over those non-zero frames. This is **functionally identical** to `per_seq_center` in `aimodel/.../recognition.py:251-256` and `aimodel/.../train.py:114-121` (`s[nz] = s[nz] - s[nz].mean(axis=0, keepdims=True)`).
   - **`_standardize`** (`sign_recognizer_service.dart:117-129`): for non-zero frames, `(x - feat_mean) / feat_std`; zero frames are left untouched (i.e. remain 0). This is **functionally equivalent** to `recognition.py:343-346` (`_infer`), which standardizes *all* frames with `(arr - feat_mean) / feat_std` and then explicitly zeroes out the zero-frame rows afterward — same end result.
   - `feat_mean`/`feat_std` are loaded from `preprocess_<dataset>.json` (`sign_recognizer_service.dart:47-52`).

6. **`seq_len`**: `static const int seqLen = 30` (`sign_recognizer_service.dart:20`), matches `preprocess_*.json` `seq_len=30` and `recognition.py`/`train.py` `SEQ_LEN=30`/`seq_len: int = 30`.

7. **Softmax/argmax location**: both performed in Dart inside `SignRecognizerService.predict()` — `_softmax` (`sign_recognizer_service.dart:131-136`) and the argmax loop (`:183-186`). The ONNX model output (`logits`) is raw, unnormalized logits — softmax is NOT baked into the exported graph.

---

## F. Recognition logic & filters

All gating/momentum logic lives in `lib/services/on_device_sign_service.dart`, class `OnDeviceSignService`.

1. **Sliding window**: `_kpBuf`, capped at `_bufSize = 30` frames (`:43-44,153-154`).

2. **Gate 1 — hand-presence gate** (`:87-93,165-176`):
   - `_hasHands(kp)` sums `abs()` of the **combined** left+right hand coordinates (indices `_faceEnd=1566` .. end, i.e. 126 values) and checks `sum > 0.05`.
   - Applied to the **last 15 frames** (`recent = _kpBuf.sublist(_kpBuf.length - 15)`); requires `handFrames >= recent.length * _minHandRatio` with **`_minHandRatio = 0.5`** (`:47`).
   - ⚠️ Differs from the Python reference `recognition.py:49-53,271`: `_has_hands` checks left-hand and right-hand sums **separately with OR** (`abs(lh).sum()>0.05 or abs(rh).sum()>0.05`), and `MIN_HAND_RATIO = 0.6` (not 0.5).

3. **Gate 2 — motion gate** (`:95-115,178-187`):
   - `_hasMotion(buf)` computes, for each of the 126 hand-coordinate columns, the **variance** across the 30-frame buffer, averages those variances, and checks `meanVariance > _minMotion^2` with **`_minMotion = 0.003`** (`:48`), i.e. threshold = `9e-6`.
   - ⚠️ Differs from the Python reference `recognition.py:56-63,272`: `_has_motion` computes the per-column **standard deviation** (not variance), averages those, and compares directly to `MIN_MOTION = 0.004` (not squared). Mean-of-variance vs. (mean-of-std)² are not mathematically equivalent, and the threshold values also differ (0.003 vs 0.004).

4. **ONNX inference** (`SignRecognizerService.predict`) is only invoked if both gates pass (`:194-197`).

5. **Confidence threshold**: `const confThresh = 0.35` (`:212`) — **matches** Python `CONF_THRESH = 0.35` (`recognition.py:267`).

6. **Momentum filter**: `static const int _momentum = 2` (`:51`); the same predicted `label` must repeat for `_streak >= _momentum` consecutive passing frames before being emitted (`:219-240`) — **matches** Python `MOMENTUM = 2` (`recognition.py:269`).

7. **Repeat/spam prevention**:
   - `_lastEmit` (`:54,227-228`): once a label is emitted, it will **not** be emitted again on subsequent frames unless a *different* label is emitted first (`label != _lastEmit` check, `:227`).
   - In `_CameraScreenState._processImage` (`camera_screen.dart:145-148`): a newly emitted word is only appended to `_words` if `!_words.contains(r.word)`, and the `_words` list is capped at **6** entries (oldest removed via `removeAt(0)`).

8. **Other differences from the Python reference (`recognition.py`)**: the Python `SignRecognizer.process_frame` only runs gating/inference every `STEP = 5` frames (`recognition.py:268,360-363`) and ends a sentence after `PAUSE_SEC = 2.5` seconds of silence (`:270`). The Dart `OnDeviceSignService` has **no frame-skip step** — gating runs on every incoming frame once the 30-frame buffer is full — and `_CameraScreenState` uses a **3-second** silence timer (`_silence = Duration(seconds: 3)`, `camera_screen.dart:61`), not 2.5s.

---

## G. Sentence generation (CRITICAL)

1. **`_composeSentence(words)`** — `lib/screens/camera_screen.dart:175-182`:
   ```dart
   String _composeSentence(List<String> words) {
     final joined = words.join(' ').trim();
     if (joined.isEmpty) return joined;
     final capitalized = joined[0].toUpperCase() + joined.substring(1);
     return RegExp(r'[.!?]$').hasMatch(capitalized)
         ? capitalized
         : '$capitalized.';
   }
   ```
   This is pure, synchronous, on-device Dart string manipulation: join words with spaces, capitalize the first letter, append `.` unless the string already ends in `.`, `!`, or `?`. **There is no LLM, no Ollama, no Qwen, and no network call of any kind.**

2. **`_buildSentence()`** — `lib/screens/camera_screen.dart:184-202`: calls `_composeSentence(ws)` synchronously, then `await HistoryService.add(TranslationEntry(...))` (shared_preferences-backed), then `setState(() { _sentence = sentence; ... })`.

3. **`api_service.dart` — DELETED**: `git status --porcelain` shows `D lib/services/api_service.dart` (deleted in the working tree, uncommitted). On `main`, this file existed and contained `ApiService.constructSentence()`, which POSTed to `$_baseUrl/sentence` (default `_defaultUrl = 'http://10.0.2.2:8000'`), with `loadUrl()`/`saveUrl()` persisting `_baseUrl` under `shared_preferences` key `backend_url` (verified via `git show main:lib/services/api_service.dart`).

4. **Repo-wide verification** — `grep -rniE "http|ollama|qwen|fastapi|/predict|/landmarks|/sentence|baseurl|api_service|10\.0\.2\.2|takePicture" lib/` returns **zero matches**. None of `api_service.dart`, `/sentence`, `/predict`, `/landmarks`, Ollama, Qwen, FastAPI, or `http` package usage exist anywhere under `lib/` in the current working tree.

5. **`http` package status**: still listed in `pubspec.lock` (version `1.6.0`) but only as `dependency: transitive` (pulled in by some other plugin, not used directly). It was removed from `pubspec.yaml`'s direct `dependencies` in this session's uncommitted change.

**Conclusion**: sentence construction is **fully on-device**. The previously existing backend `/sentence` request structure (`api_service.dart`, Ollama/Qwen2.5) has been **completely removed** from the Flutter app on this branch's working tree.

---

## H. Other features

1. **TTS** — package `flutter_tts: ^4.2.5` (`pubspec.yaml:22`, resolved `4.2.5`). `_CameraScreenState._tts = FlutterTts()` (`camera_screen.dart:34`). `_speak()` (`camera_screen.dart:205-210`):
   ```dart
   Future<void> _speak() async {
     if (_sentence.isEmpty) return;
     await _tts.stop();
     await _tts.setLanguage(_language == 'tr' ? 'tr-TR' : 'en-US');
     await _tts.speak(_sentence);
   }
   ```
   Languages: `tr-TR` and `en-US`, selected by the `_language` field (the same field that selects the recognition model, see item 3 below). `flutter_tts` wraps each platform's built-in offline TTS engine (iOS `AVSpeechSynthesizer` / Android `TextToSpeech`) — no network call is made by this package for speech synthesis. Triggered by the "Speak"/"Sesli Oku" `_ActionButton` (`camera_screen.dart:459-465`). `dispose()` also calls `_tts.stop()` (`camera_screen.dart:233`).

2. **Disclaimer dialog** — new file `lib/widgets/disclaimer_dialog.dart` (untracked), exports:
   ```dart
   Future<void> showDisclaimerDialog(BuildContext context, {required bool isTr, bool barrierDismissible = true})
   ```
   - **First launch**: `_MainShellState` in `lib/main.dart` defines `static const _disclaimerSeenKey = 'disclaimer_seen'` (`main.dart:56`); `initState()` registers `addPostFrameCallback(_maybeShowDisclaimer)` (`main.dart:69`); `_maybeShowDisclaimer()` (`main.dart:72-79`) checks `SharedPreferences` for `disclaimer_seen`, and if not set, shows the dialog with `barrierDismissible: false`, then persists `disclaimer_seen = true`.
   - **Settings**: `lib/screens/settings_screen.dart:123-129`, a `_TapTile` in the PRIVACY section titled `'Önemli not'`/`'Important notice'`, calling `showDisclaimerDialog(context, isTr: isTr)` (default `barrierDismissible: true`, dismissible, does not touch the `disclaimer_seen` flag).

3. **Language switching — two independent mechanisms**:
   - **Recognition/model language**: `_language` field in `_CameraScreenState` (`camera_screen.dart:44`, default `'en'`), toggled via `_LangButton` widgets `'TR (AUTSL)'` / `'EN (ASL)'` (`camera_screen.dart:251-269`). Switching calls `_clear()` and re-runs `_initOnDevice()` → `OnDeviceSignService.initialize(_language)` → `SignRecognizerService.initialize(language)` which loads `model_autsl.onnx`+`preprocess_autsl.json` for `'tr'` or `model_asl_citizen.onnx`+`preprocess_asl_citizen.json` otherwise (`sign_recognizer_service.dart:31-55`). This same `_language` value also drives the TTS locale (item 1) and the `TranslationType` written to history (`camera_screen.dart:193`: `_language == 'tr' ? TranslationType.TSID : TranslationType.TID`).
   - **UI text language**: `LanguageNotifier` (`lib/services/language_notifier.dart`), a `ChangeNotifier` with `isTurkish` getter and `setLanguage(String lang)` (lines 3-13), toggled via `_UiLangToggle`/`_UiLangOption` widgets (`camera_screen.dart:801-862`) and used throughout the UI (`context.watch<LanguageNotifier>().isTurkish`) to pick Turkish vs. English labels.
   - These two are **independent state** — e.g. the UI can be in English while the active recognition model is AUTSL (TR), or vice versa.

4. **History storage**: `lib/services/history_service.dart` — `SharedPreferences` key `'translation_history'` (`:6`), stored as a `List<String>` of JSON-encoded `TranslationEntry` objects. `load()` (`:8-15`) decodes and returns them reversed (most recent first); `add(entry)` (`:17-22`) appends a JSON-encoded entry; `clear()` (`:24-27`) removes the key entirely. `TranslationEntry` (`lib/models/translation_entry.dart`) has fields `id`, `text`, `type` (`enum TranslationType { TSID, TID }`, line 1 — meaning of these two acronyms is **uncertain**, not documented in code), `createdAt`.

5. **Settings screen — backend URL field**: `lib/screens/settings_screen.dart` has **no** backend-URL/API-URL field. The PRIVACY section (`:106-130`) contains exactly three `_TapTile`s: "Clear history" (`_confirmClear`), "Privacy policy" (`_showPrivacyPolicy`), and "Important notice" (disclaimer, item 2 above). The OUTPUT section (`:70-99`) has a subtitle-size picker and a "Save history" toggle (`_saveHistory` — **uncertain** whether this toggle actually gates `HistoryService.add()` calls; `_saveHistory` is read nowhere else in this file and `camera_screen.dart`'s `_buildSentence` calls `HistoryService.add` unconditionally — see Section J item 7).

6. **Benchmark overlay**: `_DebugOverlay` widget (`camera_screen.dart:504-544`), shown when `const bool kShowDebugOverlay = true` (`camera_screen.dart:24`). Displays four lines: `FPS: $fps`, `MP : $mediapipeMs ms`, `INF: $inferenceMs ms`, `TOT: ${mediapipeMs + inferenceMs} ms`, `EP : $provider`. Data sources:
   - `mediapipeMs`/`inferenceMs`: `Stopwatch`-measured in `OnDeviceSignService.processFrame` (`on_device_sign_service.dart:133-141` for MediaPipe extraction, `:195-203` for ONNX inference), returned via `FrameResult.mediapipeMs`/`inferenceMs` (`on_device_sign_service.dart:13-14`).
   - `fps`: counted in `_CameraScreenState._processImage` (`camera_screen.dart:154-163`), gated by `OnDeviceSignService.kBenchmark = true` (`on_device_sign_service.dart:37`) — logs `[BENCH] FPS: $_frameCount` once per second.
   - `provider`: `OnDeviceSignService.activeProvider` → `SignRecognizerService.activeProvider` (`sign_recognizer_service.dart:29,23`), a string set to `'NNAPI'`, `'CoreML'`, or `'CPU'` (see Section E item 1 and Section J item 3 for caveats about what this string actually represents).

---

## I. Removed vs. old architecture

Compared against `main` (verified via `git show main:lib/services/api_service.dart` and `git show main:lib/screens/camera_screen.dart`):

| Old architecture element (on `main`, and as described in the report) | Status on `feature/live-camera-stream` working tree |
|---|---|
| `lib/services/api_service.dart` (`ApiService`, HTTP POST to `/sentence`) | **Removed** — file deleted (`git status`: `D lib/services/api_service.dart`) |
| `Timer.periodic(Duration(milliseconds: 100))` capture loop (`camera_screen.dart` on `main`, lines 112-118) | **Removed** — replaced by `CameraController.startImageStream()` + busy-flag (Section C) |
| `_cam.takePicture()` + `file.readAsBytes()` + `base64Encode(bytes)` (`main` lines 121-127) | **Removed** — raw `CameraImage` planes are passed directly to native code (Section C/D) |
| `POST $_baseUrl/sentence` (Ollama/Qwen2.5 sentence construction) | **Removed** — replaced by on-device `_composeSentence()` (Section G) |
| `POST /predict`, `POST /landmarks` endpoints (described in report / `main`-era `README.md`) | **Not present anywhere in `lib/`** — keypoint extraction is native on-device MediaPipe (Section D), classification is on-device ONNX (Section E). `grep` for `/predict` and `/landmarks` in `lib/` returns 0 matches. |
| `shared_preferences` key `backend_url` (`ApiService.loadUrl`/`saveUrl` on `main`) | **Removed** along with `api_service.dart`; not referenced anywhere in the current `lib/` |
| `http` package as a direct dependency | **Removed from `pubspec.yaml`** (now transitive only, v1.6.0, unused in `lib/`) |
| FastAPI / Ollama / Qwen2.5 (backend, separate `capstone_final`/`aimodel` repo) | **Out of scope of `Capstone4992`** — no longer referenced from the Flutter app at all. The Python repo (`aimodel/real-time-sign-language-recognition-and-translation`) still contains `main.py`, `recognition.py`, `train.py`, `convert_to_onnx.py`, but these are now used only as the **offline model-training/export toolchain** (Section E item 4-5), not as a runtime backend for the app. |

**Nothing from the old server-based architecture remains reachable from the Flutter app's code.**

---

## J. Ambiguities / contradictions

1. **MediaPipe Tasks Vision version mismatch**: iOS uses `0.10.35` (`ios/Podfile.lock`), Android uses `0.10.14` (`android/app/build.gradle.kts:44`). Both bundle the *same* `holistic_landmarker.task` (Section D item 3), but the surrounding Tasks Vision library/runtime differs by platform. Whether this causes behavioral differences between platforms is **uncertain** — would require runtime testing on both platforms.

2. **Gating thresholds diverge from the Python reference implementation** (`aimodel/.../recognition.py`): `MIN_HAND_RATIO` (Dart 0.5 vs Python 0.6), `MIN_MOTION` (Dart 0.003, compared as variance, vs Python 0.004, compared as std), no `STEP=5` frame-skip in Dart, and a 3s silence timer vs. Python's `PAUSE_SEC=2.5`. The **model preprocessing** (`_perSeqCenter`/`_standardize`) matches exactly (Section E item 5), but the **live gating heuristics** are a re-implementation, not a byte-identical port — see Section F items 2,3,8.

3. **`activeProvider` may not reflect the actual runtime execution provider**: `_activeProvider` is set to `'NNAPI'`/`'CoreML'`/`'CPU'` at session-build time based on platform (`sign_recognizer_service.dart:64-73`), inside a `try`/`catch` around `appendNnapiProvider`/`appendCoreMLProvider` succeeding — it does **not** verify which EP ONNX Runtime actually dispatches each op to at inference time. The code's own comment (`:58-59`) acknowledges that unsupported quantized ops (`MatMulInteger`, `DynamicQuantizeLSTM`) automatically fall back to XNNPACK/CPU. So the `[BENCH] EP:` overlay value is the **configured** provider, not necessarily the **executing** provider for every op. Confirming the actual op-level EP assignment would require ONNX Runtime profiling on-device — **uncertain** without that.

4. **`README.md` (committed on `feature/live-camera-stream`) is itself stale relative to the current working tree**: it describes a *hybrid* architecture — on-device keypoints+ONNX classification, but sentence construction via a backend `/sentence` (Ollama/Qwen2.5) endpoint, with `lib/services/api_service.dart` listed in the project structure and `http` listed as a dependency. As of this session's uncommitted changes, `api_service.dart` is deleted, `http` is no longer a direct dependency, and sentence construction is fully on-device (Section G). `README.md` has not been updated to reflect this.

5. **"Multilingual" claim is asymmetric**: TR/AUTSL has 226 classes (`preprocess_autsl.json`, `val_acc≈0.894`), EN/ASL-Citizen has only 20 classes (`preprocess_asl_citizen.json`, `val_acc≈0.682`). Both are real, separate on-device models, but the English vocabulary is far smaller than the Turkish one — whether the report's "multilingual" framing should caveat this size/accuracy asymmetry is a presentation choice, not a code question.

6. **`_hasHands` combines both hands into one sum**, vs. the Python reference checking each hand separately with OR (Section F item 2) — functionally similar in most cases (if either hand is present its contribution dominates the sum) but not identical at the margins (e.g. two very-low-magnitude hand detections that individually fail 0.05 could sum above 0.05 in Dart but fail both checks in Python).

7. **`_saveHistory` toggle in Settings appears to be dead state**: `lib/screens/settings_screen.dart` declares `bool _saveHistory = true` (`:17`) with a `_ToggleTile` (`:91-98`), but this field is never read by `camera_screen.dart`'s `_buildSentence` (`:190-195`), which calls `HistoryService.add(...)` unconditionally. Whether this toggle is meant to gate history-saving and is simply not wired up, or is intentionally a placeholder, is **uncertain** from the code alone.

8. **Pruning**: no pruning-related code was found in `aimodel/.../convert_to_onnx.py` (only `quantize_dynamic` with `QuantType.QInt8`, Section E item 4). This is consistent with the Phase-2 finding that the report's pruning claim is not backed by code, but a full repo-wide search for pruning utilities was not re-run in this pass — **uncertain** whether pruning code exists elsewhere in `aimodel` outside the files inspected (`convert_to_onnx.py`, `recognition.py`, `train.py`, `main.py`).

---

## Report correction summary

The most critical statements in the current report's Abstract/technical sections that are **FALSE** against this codebase (`feature/live-camera-stream`):

1. **"FastAPI server with `/predict`, `/landmarks`, `/sentence` endpoints"** — FALSE for the current app. `lib/services/api_service.dart` (the only file that ever called these endpoints) is **deleted**; a repo-wide `grep` for `/predict`, `/landmarks`, `/sentence`, `fastapi`, `http` in `lib/` returns zero matches (Section G item 4, Section I).

2. **"Camera captures a frame via `takePicture()` every 100ms, encoded as base64 JPEG"** — FALSE. The current pipeline uses `CameraController.startImageStream()` (`camera_service.dart:35`) delivering raw YUV420 (Android) / BGRA8888 (iOS) frames at the camera's native rate, throttled only by a `_capturing` busy-flag — no timer, no JPEG, no base64 (Section C, Section I).

3. **"Sentence construction via Ollama/Qwen2.5 LLM (backend)"** — FALSE. `_composeSentence()` (`camera_screen.dart:175-182`) is a pure on-device string-join/capitalize/punctuate function. No LLM, Ollama, or Qwen reference exists anywhere in `lib/` (Section G).

4. **"Keypoint extraction / sign classification happens on a Python server"** — FALSE. MediaPipe `HolisticLandmarker` runs natively on-device with the **GPU delegate** on both iOS (`MediaPipePlugin.swift:83`) and Android (`MediaPipePlugin.kt:67`); classification runs on-device via ONNX Runtime 1.15.1 with NNAPI (Android) / CoreML (iOS) execution providers (`sign_recognizer_service.dart:60-77`) (Section D, E).

5. **"TFLite model"** — FALSE. The models are `.onnx` files (`assets/models/model_autsl.onnx`, `model_asl_citizen.onnx`), loaded via `OrtSession.fromBuffer` (`sign_recognizer_service.dart:39`), INT8 dynamically quantized (Section E item 2,4).

6. **"Model pruning applied"** — not supported by the code found. Only INT8 dynamic quantization (`QuantType.QInt8`) was located in the export pipeline (`aimodel/.../convert_to_onnx.py:84`); no pruning step was found (Section E item 4, Section J item 8).

7. **"No text-to-speech / no usage disclaimer in the app"** — now FALSE as of this session's (uncommitted) changes: `flutter_tts` is integrated with a "Speak"/"Sesli Oku" button (`camera_screen.dart:205-210,459-465`), and a disclaimer dialog is shown on first launch and from Settings (`lib/widgets/disclaimer_dialog.dart`, `main.dart:56,69,72-79`, `settings_screen.dart:123-129`) (Section H items 1-2).

8. **"100ms polling → 30-frame buffer ≈ 3 seconds of video at 25fps"** (timing model from `main`'s `README.md`) — FALSE for the current pipeline. The 30-frame buffer (`on_device_sign_service.dart:44`, `_bufSize=30`) still exists, but frames arrive at the camera's native streaming rate (not a fixed 100ms timer), so the buffer no longer corresponds to a fixed ~3-second window — its real-world duration depends on the achieved on-device FPS, visible via the `[BENCH] FPS` overlay (Section C, Section H item 6).
