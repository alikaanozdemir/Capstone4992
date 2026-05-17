# Sign App — Flutter Frontend

İşaret dili çeviri uygulaması. Görseldeki tasarımı birebir Flutter/Dart ile yeniden oluşturur.

## Ekranlar
- **Kamera (Canlı Detection)** — El tespiti kutusu, animasyonlu CANLI rozeti, güven skoru, keyword chip'leri, metin balonu
- **Geçmiş** — Arama, TSİD/TİD badge'leri, zaman damgaları
- **Ayarlar** — Kullanıcı kartı, toggle'lar, picker bottom sheet'ler

---

## Kurulum

### Gereksinimler
- Flutter SDK ≥ 3.0.0 → https://flutter.dev/docs/get-started/install
- Xcode ≥ 14 (iOS için)
- Android Studio (Android için)

### Adımlar

```bash
# 1. Proje dizinine gir
cd sign_app

# 2. Bağımlılıkları yükle
flutter pub get

# 3. iOS için pod'ları yükle
cd ios && pod install && cd ..

# 4. Çalıştır
# iOS Simulator:
flutter run -d iPhone                  # Xcode Simulator seçer

# Android Emulator:
flutter run -d emulator-5554           # Android Studio emülatörü
# ya da sadece:
flutter run                            # bağlı cihazı/emülatörü otomatik seçer
```

---

## Proje Yapısı

```
lib/
├── main.dart                  ← Uygulama girişi + bottom nav kabuğu
├── theme/
│   └── app_theme.dart         ← Renkler, tipografi, ThemeData
├── models/
│   └── translation_entry.dart ← Çeviri modeli + mock veriler
├── widgets/
│   ├── bottom_nav.dart        ← Alt navigasyon çubuğu
│   └── type_badge.dart        ← TSİD / TİD rozet widget'ı
└── screens/
    ├── camera_screen.dart     ← Kamera / Canlı Detection ekranı
    ├── history_screen.dart    ← Geçmiş ekranı
    └── settings_screen.dart   ← Ayarlar ekranı
```

---

## Backend Entegrasyonu

Backend hazır olduğunda değiştirilecek yerler:

### Kamera → Model sonuçları (`camera_screen.dart`)
```dart
// Şu an sabit:
final String _detectedText = 'Merhaba, ben doktorunuzum...';
final List<String> _keywords = ['MERHABA', 'BEN', 'DOKTOR'];

// Backend'den WebSocket/HTTP ile alınacak:
// ws://your-api/stream  → { text, keywords, confidence }
```

### Geçmiş (`history_screen.dart`)
```dart
// Şu an: mock veriler (models/translation_entry.dart)
// Değiştirilecek: GET /api/history  → List<TranslationEntry>
```

### Ayarlar — Kullanıcı (`settings_screen.dart`)
```dart
// Şu an: hardcoded 'Ayşe Yılmaz', 'Pro plan · TSİD + TİD'
// Değiştirilecek: GET /api/user/profile
```

---

## Kamera Entegrasyonu (Gerçek Kamera)

Gerçek kamera feed'i için `camera` paketini ekle:

```yaml
# pubspec.yaml'a ekle:
dependencies:
  camera: ^0.10.5+9
```

`camera_screen.dart` içindeki fake kamera alanını `CameraPreview(controller)` ile değiştir.

iOS için `Info.plist`'e izin ekle:
```xml
<key>NSCameraUsageDescription</key>
<string>İşaret dili algılaması için kamera gereklidir.</string>
```

Android için `AndroidManifest.xml`'e:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```
