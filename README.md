# Sign App — Flutter Mobil Uygulaması

Gerçek zamanlı işaret dili çeviri uygulaması. Kameradan 30'ar frame'lik pencereler alır, Python backend'e göndererek kelime tahmini yapar ve Ollama/Qwen2.5 ile akıcı cümle oluşturur.

Türk İşaret Dili (TID/AUTSL) ve Amerikan İşaret Dili (ASL/WLASL) desteklenmektedir.

---

## Özellikler

- **Gerçek zamanlı kamera akışı** — 100 ms'de bir frame yakalayarak 30-frame tampon oluşturur
- **İskelet overlay** — vücut pozu ve el landmarkları canlı olarak kamera görüntüsü üzerine çizilir
- **Dil seçimi** — TR (AUTSL) ve EN (WLASL) modelleri arasında geçiş
- **Cümle üretimi** — 3 saniyelik sessizlikten sonra kelimeler otomatik olarak cümleye dönüştürülür
- **Geçmiş ekranı** — önceki çeviriler kaydedilip listelenir
- **Ayarlar ekranı** — backend URL değiştirme (farklı cihazlar için LAN IP desteği)

---

## Ekranlar

| Ekran | Açıklama |
|---|---|
| Kamera | Frame yakalama, iskelet overlay, kelime chip'leri, cümle paneli |
| Geçmiş | Kaydedilmiş çeviriler |
| Ayarlar | Backend URL yapılandırması |

---

## Backend Kurulumu

Uygulama, ayrı bir Python FastAPI sunucusuna ihtiyaç duyar. Kurulum için `capstone_final/` dizinindeki `README.md` dosyasına bakın.

### Backend Adresi

Uygulamayı başlatmadan önce doğru backend adresini Ayarlar ekranından girin:

| Platform | Adres |
|---|---|
| Android emülatör | `http://10.0.2.2:8000` |
| iOS simülatör | `http://localhost:8000` |
| Gerçek cihaz | `http://<bilgisayarın_LAN_IP>:8000` |

Varsayılan adres `http://10.0.2.2:8000` olarak ayarlanmıştır.

---

## Kurulum ve Çalıştırma

### Gereksinimler

- Flutter SDK `>=3.0.0`
- Xcode (iOS için) veya Android Studio (Android için)
- Çalışan `capstone_final` backend sunucusu

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
Kamera (100ms/frame)
      │
      ▼
30-frame tampon (base64 JPEG)
      │
      ├── POST /predict   → kelime + güven skoru
      │
      ├── POST /landmarks → pose + el koordinatları (iskelet overlay)
      │
      └── 3 sn sessizlik sonra
             POST /sentence  → akıcı cümle (Ollama/Qwen2.5)
```

1. Uygulama açılınca backend'e `/health` isteği atar; bağlantı durumunu gösterir.
2. Her 100 ms'de kamera frame'i base64 JPEG olarak kodlanır ve tampona eklenir.
3. Tampon 30 frame'e dolduğunda `/predict` endpoint'ine gönderilir.
4. Aynı anda `/landmarks` endpoint'i ile her frame'in iskelet verisi alınarak kamera önizlemesi üzerine çizilir.
5. Yeni bir kelime algılandığında 3 saniyelik sessizlik sayacı sıfırlanır.
6. 3 saniye boyunca yeni kelime gelmezse `/sentence` endpoint'ine kelime listesi gönderilir ve akıcı cümle gösterilir.

---

## Proje Yapısı

```
Capstone4992/
├── lib/
│   ├── main.dart                  # Uygulama giriş noktası
│   ├── screens/
│   │   ├── camera_screen.dart     # Ana tanıma ekranı
│   │   ├── history_screen.dart    # Çeviri geçmişi
│   │   └── settings_screen.dart   # Backend URL ayarları
│   ├── services/
│   │   ├── api_service.dart       # HTTP istemcisi (predict/sentence/landmarks)
│   │   └── camera_service.dart    # Kamera yönetimi
│   ├── models/
│   │   ├── prediction_result.dart # Tahmin modeli
│   │   └── translation_entry.dart # Geçmiş kaydı modeli
│   ├── widgets/
│   │   ├── bottom_nav.dart        # Alt navigasyon barı
│   │   └── type_badge.dart        # Dil rozeti widget'ı
│   └── theme/
│       └── app_theme.dart         # Renk paleti ve tema
├── ios/
├── pubspec.yaml
└── analysis_options.yaml
```

---

## Bağımlılıklar

| Paket | Kullanım |
|---|---|
| `camera` | Kamera akışı ve frame yakalama |
| `http` | Backend ile REST iletişimi |
| `shared_preferences` | Backend URL kalıcı saklama |
| `provider` | Durum yönetimi |
| `google_fonts` | Tipografi |
| `flutter_animate` | Geçiş animasyonları |
| `go_router` | Sayfa yönlendirmesi |
| `permission_handler` | Kamera izin yönetimi |
