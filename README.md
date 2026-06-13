# Sign App — Flutter Mobil Uygulaması

Gerçek zamanlı işaret dili çeviri uygulaması. Kamera görüntüsünden keypoint çıkarımı ve kelime tanıma **tamamen cihaz üzerinde (on-device)** yapılır; sadece tanınan kelime listesinden akıcı bir cümle oluşturmak için Ollama/Qwen2.5 çalıştıran bir backend kullanılır.

Türk İşaret Dili (TİD/AUTSL, 226 sınıf) ve Amerikan İşaret Dili (ASL Citizen, 20 sınıf) desteklenmektedir.

---

## Özellikler

- **On-device keypoint çıkarımı** — her platformun native MediaPipe HolisticLandmarker'ı (iOS: Swift / Android: Kotlin) kameradan gelen kareyi 1692 boyutlu bir keypoint vektörüne (pose 132 + face 1434 + sol el 63 + sağ el 63) dönüştürür
- **On-device kelime tanıma** — INT8 dinamik quantize edilmiş ONNX modeli (ONNX Runtime ile) 30 karelik pencereler üzerinde sınıflandırma yapar; hareket/el varlığı kontrolleri (gate) ve momentum filtresiyle gürültü azaltılır
- **İskelet overlay** — vücut pozu ve el landmarkları canlı olarak kamera görüntüsü üzerine çizilir
- **Dil seçimi** — TR (AUTSL) ve EN (ASL Citizen) modelleri arasında geçiş
- **Cümle üretimi** — 3 saniyelik sessizlikten sonra tanınan kelimeler, backend üzerindeki Ollama/Qwen2.5 ile akıcı bir cümleye dönüştürülür (backend'e ulaşılamazsa kelimeler boşlukla birleştirilerek gösterilir)
- **Geçmiş ekranı** — önceki çeviriler cihazda yerel olarak kaydedilip listelenir
- **Ayarlar ekranı** — görünüm, altyazı boyutu, geçmiş ve gizlilik tercihleri

---

## Ekranlar

| Ekran | Açıklama |
|---|---|
| Kamera | Frame yakalama, on-device tanıma, iskelet overlay, kelime chip'leri, cümle paneli |
| Geçmiş | Kaydedilmiş çeviriler |
| Ayarlar | Görünüm, altyazı, geçmiş ve gizlilik ayarları |

---

## Backend Kurulumu (opsiyonel)

Kelime tanıma ve keypoint çıkarımı için backend **gerekmez** — bunlar cihaz üzerinde çalışır. Backend yalnızca tanınan kelime listesinden doğal dilde bir cümle oluşturmak (`/sentence`, Ollama/Qwen2.5) için kullanılır. Backend çalışmıyorsa uygulama, kelimeleri boşlukla birleştirip cümle olarak gösterir.

Kurulum için `capstone_final/` dizinindeki `README.md` dosyasına bakın.

Varsayılan adres `ApiService` içinde `http://10.0.2.2:8000` (Android emülatör) olarak ayarlıdır; farklı bir cihazda çalıştırırken `lib/services/api_service.dart` içindeki `_defaultUrl` değerini güncelleyin.

---

## Kurulum ve Çalıştırma

### Gereksinimler

- Flutter SDK `>=3.0.0`
- Xcode (iOS için) veya Android Studio (Android için)
- (Opsiyonel) Cümle üretimi için çalışan `capstone_final` backend sunucusu

### Bağımlılıkları Yükle

```bash
cd Capstone4992
flutter pub get
```

### iOS

```bash
cd ios && pod install && cd ..
flutter run
```

### Android

```bash
flutter run
```

---

## Nasıl Çalışır

```
Kamera (100ms/frame, JPEG → base64)
      │
      ▼
Native MediaPipe HolisticLandmarker (iOS Swift / Android Kotlin)
      │   → 1692-dim keypoint vektörü (pose 132 + face 1434 + lh 63 + rh 63)
      ▼
30 karelik tampon
      │
      ├── Gate 1: son karelerin yarısında el var mı?
      ├── Gate 2: yeterli hareket var mı?
      ▼
ONNX Runtime (on-device, AUTSL / ASL Citizen modeli)
      │   → kelime + güven skoru (momentum filtresiyle onaylanır)
      ▼
Kelime listesi
      │
      └── 3 sn sessizlik sonra
             POST /sentence  → akıcı cümle (Ollama/Qwen2.5, backend)
```

1. Uygulama açılışta seçili dile göre (`tr` → AUTSL, `en` → ASL Citizen) ONNX modelini ve native MediaPipe landmarker'ı yükler.
2. Her 100 ms'de bir kamera karesi base64 JPEG olarak native MediaPipe köprüsüne (`mediapipe_channel_service.dart`) gönderilir ve 1692-dim keypoint vektörü alınır.
3. Keypoint'ler 30 karelik bir tampona eklenir; pose/el verileri kamera önizlemesi üzerine iskelet olarak çizilir.
4. Tampon dolduğunda el varlığı ve hareket kontrolleri (gate) geçilirse ONNX modeli çalıştırılır ve kelime + güven skoru üretilir.
5. Aynı kelime üst üste yeterince tekrar edip (momentum) önceki tahminden farklıysa kelime listesine eklenir ve sessizlik sayacı sıfırlanır.
6. 3 saniye boyunca yeni kelime gelmezse kelime listesi backend'in `/sentence` endpoint'ine gönderilir ve akıcı cümle gösterilir.

---

## Proje Yapısı

```
Capstone4992/
├── lib/
│   ├── main.dart                          # Uygulama giriş noktası
│   ├── screens/
│   │   ├── camera_screen.dart             # Ana tanıma ekranı
│   │   ├── history_screen.dart            # Çeviri geçmişi
│   │   └── settings_screen.dart           # Görünüm/altyazı/gizlilik ayarları
│   ├── services/
│   │   ├── api_service.dart               # /sentence için HTTP istemcisi
│   │   ├── camera_service.dart            # Kamera yönetimi
│   │   ├── mediapipe_channel_service.dart # Flutter ↔ native MediaPipe köprüsü
│   │   ├── on_device_sign_service.dart    # Gate + momentum filtreli pipeline
│   │   ├── sign_recognizer_service.dart   # ONNX Runtime inference
│   │   ├── history_service.dart           # Geçmiş kayıtları
│   │   ├── language_notifier.dart         # Arayüz dili
│   │   └── theme_notifier.dart            # Açık/koyu tema
│   ├── models/
│   │   └── translation_entry.dart         # Geçmiş kaydı modeli
│   ├── widgets/
│   │   ├── bottom_nav.dart                 # Alt navigasyon barı
│   │   └── type_badge.dart                 # Dil rozeti widget'ı
│   └── theme/
│       └── app_theme.dart                  # Renk paleti ve tema
├── assets/models/                          # ONNX modeller + preprocessing meta verisi
├── ios/Runner/MediaPipePlugin.swift        # iOS native HolisticLandmarker
├── android/app/.../MediaPipePlugin.kt      # Android native HolisticLandmarker
├── pubspec.yaml
└── analysis_options.yaml
```

---

## Bağımlılıklar

| Paket | Kullanım |
|---|---|
| `camera` | Kamera akışı ve frame yakalama |
| `onnxruntime` | On-device ONNX model inference (AUTSL / ASL Citizen) |
| `http` | Cümle üretimi için backend ile REST iletişimi |
| `shared_preferences` | Kalıcı ayar saklama |
| `provider` | Durum yönetimi |
| `google_fonts` | Tipografi |
| `flutter_animate` | Geçiş animasyonları |
| `go_router` | Sayfa yönlendirmesi |
| `permission_handler` | Kamera izin yönetimi |

Native taraf (pubspec dışı): iOS'te `MediaPipeTasksVision` (CocoaPods), Android'de MediaPipe Tasks Vision (Gradle) — `holistic_landmarker.task` model dosyasıyla birlikte.
