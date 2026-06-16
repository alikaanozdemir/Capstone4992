import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/camera_service.dart';
import '../services/mediapipe_channel_service.dart';
import '../services/on_device_sign_service.dart';
import '../services/history_service.dart';
import '../services/language_notifier.dart';
import '../services/nmt_service.dart';
import '../models/translation_entry.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

/// Kamera preview üzerinde [BENCH] metriklerini canlı gösteren debug overlay.
/// Üretim build'inde kapatmak için `false` yapın.
const bool kShowDebugOverlay = true;

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _dotController;
  late Animation<double> _pulseAnim;

  final CameraService _cam = CameraService();
  final OnDeviceSignService _onDevice = OnDeviceSignService();
  final NmtService _nmt = NmtService();
  final FlutterTts _tts = FlutterTts();

  bool _camReady = false;
  bool _onDeviceReady = false;
  String _statusMsg = 'Starting...';

  String _sentence = '';
  final _words = <String>[];
  double _confidence = 0.0;
  bool _thinking = false;
  String _language = 'en';

  List<double>? _poseLandmarks;
  List<double>? _lhLandmarks;
  List<double>? _rhLandmarks;

  // NMT çeviri durumu
  String _translationTarget = 'none'; // 'none' | 'en' | 'fr'
  String _translatedSentence = '';
  bool _translating = false;

  bool _capturing = false;

  int _frameCount = 0;
  DateTime _fpsStart = DateTime.now();

  // Debug overlay metrikleri (bkz. kShowDebugOverlay)
  int _currentFps = 0;
  int _lastMediapipeMs = 0;
  int _lastInferenceMs = 0;

  Timer? _silenceTimer;
  static const Duration _silence = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startup();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _startup() async {
    _nmt.initialize(); // lazy — modeller arka planda yüklenir
    _initOnDevice();
    try {
      await _cam.initialize();
      if (mounted) {
        setState(() { _camReady = true; _statusMsg = 'Ready'; });
        _startCapture();
      }
    } catch (e) {
      if (mounted) setState(() => _statusMsg = 'Camera error: $e');
    }
  }

  Future<void> _initOnDevice() async {
    try {
      await _onDevice.initialize(_language);
      if (mounted) setState(() => _onDeviceReady = true);
    } catch (e, st) {
      debugPrint('[OnDevice INIT ERROR] $e\n$st');
      if (mounted) setState(() => _onDeviceReady = false);
    }
  }

  void _startCapture() {
    _cam.startImageStream(_onCameraImage);
  }

  /// Kamera akışından gelen her kare için çağrılır (Android: YUV420, iOS: BGRA8888).
  /// MediaPipe/ONNX 30fps'e yetişemediği için işlenmekte olan bir kare varsa
  /// gelen yeni kareler atlanır.
  void _onCameraImage(CameraImage image) {
    if (_capturing || !_camReady || !_onDeviceReady) return;
    _capturing = true;
    _processImage(image).whenComplete(() => _capturing = false);
  }

  CameraFrame _toCameraFrame(CameraImage image) {
    return CameraFrame(
      width: image.width,
      height: image.height,
      rotationDegrees: _cam.sensorOrientation,
      planes: image.planes.map((p) => p.bytes).toList(),
      bytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
      bytesPerPixel: image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
    );
  }

  Future<void> _processImage(CameraImage image) async {
    try {
      final frame = _toCameraFrame(image);
      final r = await _onDevice.processFrame(frame);
      if (!mounted) return;
      setState(() {
        _confidence = r.confidence;
        if (r.poseLm != null) {
          _poseLandmarks = r.poseLm;
          _lhLandmarks   = r.lhLm;
          _rhLandmarks   = r.rhLm;
        }
        if (r.word != null && !_words.contains(r.word)) {
          _words.add(r.word!);
          if (_words.length > 6) _words.removeAt(0);
        }
        if (r.mediapipeMs != null) _lastMediapipeMs = r.mediapipeMs!;
        if (r.inferenceMs != null) _lastInferenceMs = r.inferenceMs!;
      });
      if (r.word != null) _resetSilence();

      if (OnDeviceSignService.kBenchmark) {
        _frameCount++;
        final dt = DateTime.now().difference(_fpsStart);
        if (dt.inMilliseconds >= 1000) {
          debugPrint('[BENCH] FPS: $_frameCount');
          if (mounted) setState(() => _currentFps = _frameCount);
          _frameCount = 0;
          _fpsStart = DateTime.now();
        }
      }
    } catch (e, st) {
      debugPrint('[CaptureFrame ERROR] $e\n$st');
    }
  }

  void _resetSilence() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silence, _buildSentence);
  }

  /// Kelimeleri tek bir cümleye birleştirir — tamamen cihaz üstü, ağ isteği yok.
  String _composeSentence(List<String> words) {
    final joined = words.join(' ').trim();
    if (joined.isEmpty) return joined;
    final capitalized = joined[0].toUpperCase() + joined.substring(1);
    return RegExp(r'[.!?]$').hasMatch(capitalized)
        ? capitalized
        : '$capitalized.';
  }

  Future<void> _buildSentence() async {
    if (_words.isEmpty) return;
    setState(() => _thinking = true);
    final ws = List<String>.from(_words);
    final sentence = _composeSentence(ws);

    // NMT çevirisi — eğer hedef dil seçiliyse
    String? translated;
    if (_translationTarget != 'none') {
      setState(() { _thinking = false; _translating = true; });
      translated = await _nmt.translate(
        sentence,
        source: _language,
        target: _translationTarget,
      );
    }

    if (!mounted) return;
    await HistoryService.add(TranslationEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: sentence,
      type: _language == 'tr' ? TranslationType.TSID : TranslationType.TID,
      createdAt: DateTime.now(),
      translatedText: translated,
      targetLang: translated != null ? _translationTarget : null,
    ));
    setState(() {
      _sentence = sentence;
      _translatedSentence = translated ?? '';
      _thinking = false;
      _translating = false;
      _words.clear();
      _confidence = 0;
    });
  }

  /// Cümleyi TTS ile seslendirir — çeviri varsa çevrilmiş metni hedef dilde okur.
  Future<void> _speak() async {
    if (_translatedSentence.isNotEmpty) {
      await _tts.stop();
      await _tts.setLanguage(_targetTtsLang());
      await _tts.speak(_translatedSentence);
    } else if (_sentence.isNotEmpty) {
      await _tts.stop();
      await _tts.setLanguage(_language == 'tr' ? 'tr-TR' : 'en-US');
      await _tts.speak(_sentence);
    }
  }

  String _targetTtsLang() {
    switch (_translationTarget) {
      case 'fr': return 'fr-FR';
      case 'en': return 'en-US';
      default:   return _language == 'tr' ? 'tr-TR' : 'en-US';
    }
  }

  void _clear() {
    _silenceTimer?.cancel();
    _onDevice.resetBuffer();
    setState(() {
      _sentence = '';
      _translatedSentence = '';
      _translating = false;
      _words.clear();
      _confidence = 0;
      _thinking = false;
      _poseLandmarks = null;
      _lhLandmarks = null;
      _rhLandmarks = null;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotController.dispose();
    _silenceTimer?.cancel();
    _cam.dispose();
    _onDevice.dispose();
    _nmt.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTr = context.watch<LanguageNotifier>().isTurkish;
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Model + UI lang selector
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  _LangButton(
                    label: 'TR (AUTSL)',
                    active: _language == 'tr',
                    onTap: () {
                      setState(() {
                        _language = 'tr';
                        _onDeviceReady = false;
                        // EN→EN anlamsız olurdu; hedefi sıfırla
                        if (_translationTarget == 'en') _translationTarget = 'none';
                      });
                      _clear();
                      _initOnDevice();
                    },
                  ),
                  const SizedBox(width: 6),
                  _LangButton(
                    label: 'EN (ASL)',
                    active: _language == 'en',
                    onTap: () {
                      setState(() {
                        _language = 'en';
                        _onDeviceReady = false;
                        // EN modelde TR→EN hedefi geçersiz
                        if (_translationTarget == 'en') _translationTarget = 'none';
                      });
                      _clear();
                      _initOnDevice();
                    },
                  ),
                  const Spacer(),
                  const _UiLangToggle(),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // NMT çeviri hedef satırı
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Text(
                    isTr ? 'Çeviri:' : 'Translate:',
                    style: TextStyle(color: AppColors.of(context).textSub, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  _TranslateChip(
                    label: isTr ? 'Yok' : 'Off',
                    active: _translationTarget == 'none',
                    onTap: () => setState(() {
                      _translationTarget = 'none';
                      _translatedSentence = '';
                    }),
                  ),
                  if (_language == 'tr') ...[
                    const SizedBox(width: 5),
                    _TranslateChip(
                      label: '→ EN',
                      active: _translationTarget == 'en',
                      onTap: () => setState(() {
                        _translationTarget = 'en';
                        _translatedSentence = '';
                      }),
                    ),
                  ],
                  const SizedBox(width: 5),
                  _TranslateChip(
                    label: '→ FR',
                    active: _translationTarget == 'fr',
                    onTap: () => setState(() {
                      _translationTarget = 'fr';
                      _translatedSentence = '';
                    }),
                  ),
                ],
              ),
            ),

            // Camera area
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1628),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _camReady && _cam.controller != null
                              ? CameraPreview(_cam.controller!)
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const CircularProgressIndicator(
                                        color: AppColors.green,
                                        strokeWidth: 2,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _statusMsg,
                                        style: const TextStyle(
                                          color: Color(0xFF8B949E),
                                          fontSize: 13,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),

                          CustomPaint(
                            size: Size.infinite,
                            painter: _GridPainter(),
                          ),

                          if (_poseLandmarks != null)
                            CustomPaint(
                              size: Size.infinite,
                              painter: _SkeletonPainter(
                                poseLandmarks: _poseLandmarks!,
                                lhLandmarks: _lhLandmarks,
                                rhLandmarks: _rhLandmarks,
                              ),
                            ),

                          if (_camReady)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              child: _LiveBadge(
                                dotController: _dotController,
                                label: isTr ? 'CANLI' : 'LIVE',
                              ),
                            ),

                          if (_confidence > 0)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.green,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '%${(_confidence * 100).round()}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                          if (kShowDebugOverlay)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: IgnorePointer(
                                child: _DebugOverlay(
                                  fps: _currentFps,
                                  mediapipeMs: _lastMediapipeMs,
                                  inferenceMs: _lastInferenceMs,
                                  provider: _onDevice.activeProvider,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Word chips
            SizedBox(
              height: 44,
              child: _words.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _words.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => _KeywordChip(label: _words[i]),
                    ),
            ),

            const SizedBox(height: 12),

            // Sentence panel
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_thinking)
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              color: AppColors.green,
                              strokeWidth: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isTr ? 'Cümle oluşturuluyor...' : 'Building sentence...',
                            style: TextStyle(color: c.textSub, fontSize: 13),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _sentence.isNotEmpty
                                ? _sentence
                                : (isTr ? 'İşaret yapmaya başlayın...' : 'Start signing...'),
                            style: TextStyle(
                              fontSize: 15,
                              color: _sentence.isNotEmpty ? c.text : c.textMuted,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                          if (_translating)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 11,
                                    height: 11,
                                    child: CircularProgressIndicator(
                                      color: AppColors.green,
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isTr ? 'Çevriliyor...' : 'Translating...',
                                    style: TextStyle(color: c.textSub, fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          else if (_translatedSentence.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.translate_rounded,
                                    size: 13,
                                    color: AppColors.green,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      _translatedSentence,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.green,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                    const Spacer(),

                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.refresh_rounded,
                            label: isTr ? 'Temizle' : 'Clear',
                            isPrimary: true,
                            onTap: _clear,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.volume_up_rounded,
                            label: isTr ? 'Sesli Oku' : 'Speak',
                            onTap: _speak,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.copy_rounded,
                            label: isTr ? 'Kopyala' : 'Copy',
                            onTap: () {
                              if (_sentence.isEmpty) return;
                              final copyText = _translatedSentence.isNotEmpty
                                  ? '$_sentence\n$_translatedSentence'
                                  : _sentence;
                              Clipboard.setData(ClipboardData(text: copyText));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isTr ? 'Kopyalandı' : 'Copied'),
                                  backgroundColor: AppColors.green,
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _DebugOverlay extends StatelessWidget {
  final int fps;
  final int mediapipeMs;
  final int inferenceMs;
  final String provider;

  const _DebugOverlay({
    required this.fps,
    required this.mediapipeMs,
    required this.inferenceMs,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.greenAccent,
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.4,
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('FPS: $fps', style: style),
          Text('MP : $mediapipeMs ms', style: style),
          Text('INF: $inferenceMs ms', style: style),
          Text('TOT: ${mediapipeMs + inferenceMs} ms', style: style),
          Text('EP : $provider', style: style),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E2D45).withOpacity(0.5)
      ..strokeWidth = 0.5;
    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

class _LiveBadge extends StatelessWidget {
  final AnimationController dotController;
  final String label;
  const _LiveBadge({required this.dotController, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: dotController,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  AppColors.green,
                  AppColors.greenLight,
                  dotController.value,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.green.withOpacity(0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '● $label',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.green,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeywordChip extends StatelessWidget {
  final String label;
  const _KeywordChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.green : c.bgCard2,
          borderRadius: BorderRadius.circular(10),
          border: isPrimary
              ? null
              : Border.all(color: c.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  final List<double> poseLandmarks;
  final List<double>? lhLandmarks;
  final List<double>? rhLandmarks;

  const _SkeletonPainter({
    required this.poseLandmarks,
    this.lhLandmarks,
    this.rhLandmarks,
  });

  static const _poseConnections = [
    [0, 1], [1, 2], [2, 3], [3, 7],
    [0, 4], [4, 5], [5, 6], [6, 8],
    [9, 10],
    [11, 12], [11, 13], [13, 15], [15, 17], [15, 19], [15, 21], [17, 19],
    [12, 14], [14, 16], [16, 18], [16, 20], [16, 22], [18, 20],
    [11, 23], [12, 24], [23, 24], [23, 25], [24, 26],
    [25, 27], [26, 28], [27, 29], [28, 30], [29, 31], [30, 32], [27, 31], [28, 32],
  ];

  static const _handConnections = [
    [0, 1], [1, 2], [2, 3], [3, 4],
    [0, 5], [5, 6], [6, 7], [7, 8],
    [5, 9], [9, 10], [10, 11], [11, 12],
    [9, 13], [13, 14], [14, 15], [15, 16],
    [13, 17], [17, 18], [18, 19], [19, 20],
    [0, 17],
  ];

  Offset _posePoint(int i, Size s) => Offset(
        poseLandmarks[i * 4] * s.width,
        poseLandmarks[i * 4 + 1] * s.height,
      );

  double _poseVis(int i) => poseLandmarks[i * 4 + 3];

  Offset _handPoint(List<double> kp, int i, Size s) => Offset(
        kp[i * 3] * s.width,
        kp[i * 3 + 1] * s.height,
      );

  bool _handPresent(List<double>? kp) {
    if (kp == null) return false;
    double sum = 0;
    for (final v in kp) {
      sum += v < 0 ? -v : v;
    }
    return sum > 0.05;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bodyLine = Paint()
      ..color = const Color(0xCC00FF88)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final bodyDot = Paint()
      ..color = const Color(0xFF00FF88)
      ..style = PaintingStyle.fill;

    final lhLine = Paint()
      ..color = const Color(0xCCFFD700)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rhLine = Paint()
      ..color = const Color(0xCC4DB8FF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final c in _poseConnections) {
      if (_poseVis(c[0]) > 0.3 && _poseVis(c[1]) > 0.3) {
        canvas.drawLine(_posePoint(c[0], size), _posePoint(c[1], size), bodyLine);
      }
    }
    for (int i = 0; i < 33; i++) {
      if (_poseVis(i) > 0.3) {
        canvas.drawCircle(_posePoint(i, size), 3.0, bodyDot);
      }
    }

    void drawHand(List<double>? kp, Paint line) {
      if (!_handPresent(kp)) return;
      final dot = Paint()
        ..color = line.color
        ..style = PaintingStyle.fill;
      for (final c in _handConnections) {
        canvas.drawLine(_handPoint(kp!, c[0], size), _handPoint(kp, c[1], size), line);
      }
      for (int i = 0; i < 21; i++) {
        canvas.drawCircle(_handPoint(kp!, i, size), 3.0, dot);
      }
    }

    drawHand(lhLandmarks, lhLine);
    drawHand(rhLandmarks, rhLine);
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      poseLandmarks != old.poseLandmarks ||
      lhLandmarks != old.lhLandmarks ||
      rhLandmarks != old.rhLandmarks;
}

class _UiLangToggle extends StatelessWidget {
  const _UiLangToggle();

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<LanguageNotifier>();
    final isTr = notifier.isTurkish;
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UiLangOption(
            label: 'TR',
            active: isTr,
            onTap: () => context.read<LanguageNotifier>().setLanguage('tr'),
          ),
          _UiLangOption(
            label: 'EN',
            active: !isTr,
            onTap: () => context.read<LanguageNotifier>().setLanguage('en'),
          ),
        ],
      ),
    );
  }
}

class _UiLangOption extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _UiLangOption({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.green : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : c.textSub,
          ),
        ),
      ),
    );
  }
}

/// NMT çeviri hedef seçici chip'i (Yok / → EN / → FR)
class _TranslateChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TranslateChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.green.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppColors.green : c.border,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? AppColors.green : c.textSub,
          ),
        ),
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _LangButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.green : c.bgCard2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.green : c.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.white : c.textSub,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
