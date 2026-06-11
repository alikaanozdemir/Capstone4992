import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/camera_service.dart';
import '../services/api_service.dart';
import '../services/on_device_sign_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  // ── Animasyonlar ──────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _dotController;
  late Animation<double> _pulseAnim;

  // ── Servisler ─────────────────────────────────────────────────────────────
  final CameraService _cam = CameraService();
  final ApiService _api = ApiService();
  final OnDeviceSignService _onDevice = OnDeviceSignService();

  // ── Durum ─────────────────────────────────────────────────────────────────
  bool _camReady = false;
  bool _onDeviceReady = false;
  String _statusMsg = 'Başlatılıyor...';

  // Tanıma çıktısı
  String _sentence = '';
  final _words = <String>[];
  double _confidence = 0.0;
  bool _thinking = false;
  String _language = 'en'; // 'tr' = AUTSL (Türkçe), 'en' = ASL Citizen (İngilizce)

  // İskelet görselleştirme
  List<double>? _poseLandmarks;
  List<double>? _lhLandmarks;
  List<double>? _rhLandmarks;

  Timer? _captureTimer;
  bool _capturing = false;

  // Sessizlik sayacı (kelime gelmeyi bırakınca cümleye dönüştür)
  Timer? _silenceTimer;
  static const Duration _silence = Duration(seconds: 3);

  // ── Init / Dispose ────────────────────────────────────────────────────────
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
    // On-device servisi arka planda başlat
    _initOnDevice();

    // Kamerayı aç
    try {
      await _cam.initialize();
      if (mounted) {
        setState(() {
          _camReady = true;
          _statusMsg = 'Hazır — işaret yapın';
        });
        _startCapture();
      }
    } catch (e) {
      if (mounted) setState(() => _statusMsg = 'Kamera hatası: $e');
    }
  }

  Future<void> _initOnDevice() async {
    try {
      await _onDevice.initialize(_language);
      if (mounted) setState(() => _onDeviceReady = true);
    } catch (e, st) {
      debugPrint('[OnDevice INIT ERROR] $e\n$st');
      if (mounted) {
        setState(() {
          _onDeviceReady = false;
          _statusMsg = 'Model yüklenemedi: $e';
        });
      }
    }
  }

  // ── Frame yakalama ────────────────────────────────────────────────────────

  void _startCapture() {
    // Her 100ms'de bir fotoğraf çek → 30 frame ≈ 3 saniye (model 25fps video ile eğitildi)
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _captureFrame(),
    );
  }

  Future<void> _captureFrame() async {
    if (_capturing || !_camReady || !_onDeviceReady) return;
    _capturing = true;
    try {
      final file = await _cam.takePicture();
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final r = await _onDevice.processFrame(b64);
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
      });
      if (r.word != null) _resetSilence();
    } catch (e, st) {
      debugPrint('[CaptureFrame ERROR] $e\n$st');
    } finally {
      _capturing = false;
    }
  }

  void _resetSilence() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silence, _buildSentence);
  }

  Future<void> _buildSentence() async {
    if (_words.isEmpty) return;
    setState(() => _thinking = true);
    final ws = List<String>.from(_words);
    final s = await _api.constructSentence(ws, language: _language);
    if (!mounted) return;
    setState(() {
      _sentence = s ?? ws.join(' ');
      _thinking = false;
      _words.clear();
      _confidence = 0;
    });
  }

  void _clear() {
    _silenceTimer?.cancel();
    _onDevice.resetBuffer();
    setState(() {
      _sentence = '';
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
    _captureTimer?.cancel();
    _silenceTimer?.cancel();
    _cam.dispose();
    _onDevice.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Dil seçici ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Model:',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                  const SizedBox(width: 8),
                  _LangButton(
                    label: 'TR (AUTSL)',
                    active: _language == 'tr',
                    onTap: () {
                      setState(() { _language = 'tr'; _onDeviceReady = false; });
                      _clear();
                      _initOnDevice();
                    },
                  ),
                  const SizedBox(width: 6),
                  _LangButton(
                    label: 'EN (ASL Citizen)',
                    active: _language == 'en',
                    onTap: () {
                      setState(() { _language = 'en'; _onDeviceReady = false; });
                      _clear();
                      _initOnDevice();
                    },
                  ),
                  const Spacer(),
                  _OnDeviceStatusBadge(ready: _onDeviceReady),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // ── Kamera alanı ──────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1628),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Gerçek kamera ya da yükleniyor
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
                                          color: AppColors.textSub,
                                          fontSize: 13,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),

                          // Grid çizgileri (hafif overlay)
                          CustomPaint(
                            size: Size.infinite,
                            painter: _GridPainter(),
                          ),

                          // İskelet overlay
                          if (_poseLandmarks != null)
                            CustomPaint(
                              size: Size.infinite,
                              painter: _SkeletonPainter(
                                poseLandmarks: _poseLandmarks!,
                                lhLandmarks: _lhLandmarks,
                                rhLandmarks: _rhLandmarks,
                              ),
                            ),

                          // Gerçek iskelet gelene kadar placeholder kutu
                          if (_camReady && _poseLandmarks == null)
                            Center(
                              child: AnimatedBuilder(
                                animation: _pulseAnim,
                                builder: (_, child) => Transform.scale(
                                  scale: _pulseAnim.value,
                                  child: child,
                                ),
                                child: const _HandDetectionBox(),
                              ),
                            ),

                          // Alt sol — CANLI rozeti
                          if (_camReady)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              child: _LiveBadge(dotController: _dotController),
                            ),

                          // Sağ üst — güven skoru
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Kelime chip'leri ──────────────────────────────────────────
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

            // ── Cümle paneli ──────────────────────────────────────────────
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Metin ya da yükleniyor
                    if (_thinking)
                      const Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              color: AppColors.green,
                              strokeWidth: 1.5,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Cümle oluşturuluyor...',
                            style: TextStyle(
                                color: AppColors.textSub, fontSize: 13),
                          ),
                        ],
                      )
                    else
                      Text(
                        _sentence.isNotEmpty
                            ? _sentence
                            : 'İşaret yapmaya başlayın...',
                        style: TextStyle(
                          fontSize: 15,
                          color: _sentence.isNotEmpty
                              ? AppColors.text
                              : AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),

                    const Spacer(),

                    // Aksiyon butonları
                    Row(
                      children: [
                        _ActionButton(
                          icon: Icons.volume_up_rounded,
                          label: 'Seslendir',
                          onTap: () {},
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.refresh_rounded,
                          label: 'Temizle',
                          isPrimary: true,
                          onTap: _clear,
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.copy_rounded,
                          label: 'Kopyala',
                          onTap: () {},
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
// Sub-widgets (orijinal tasarım korundu)
// ═══════════════════════════════════════════════════════════════════════════

class _HandDetectionBox extends StatelessWidget {
  const _HandDetectionBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.green, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Stack(
        children: [
          ..._buildCorners(),
          Center(
            child: Icon(
              Icons.back_hand_outlined,
              size: 80,
              color: AppColors.green.withValues(alpha: 0.3),
            ),
          ),
          ..._buildSkeletonDots(),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const size = 14.0;
    const thick = 2.5;
    const color = AppColors.greenLight;
    return const [
      Positioned(top: -1, left: -1, child: _Corner(color: color, size: size, thickness: thick, topLeft: true)),
      Positioned(top: -1, right: -1, child: _Corner(color: color, size: size, thickness: thick, topRight: true)),
      Positioned(bottom: -1, left: -1, child: _Corner(color: color, size: size, thickness: thick, bottomLeft: true)),
      Positioned(bottom: -1, right: -1, child: _Corner(color: color, size: size, thickness: thick, bottomRight: true)),
    ];
  }

  List<Widget> _buildSkeletonDots() {
    const positions = [
      Offset(0.5, 0.15), Offset(0.35, 0.25), Offset(0.65, 0.25),
      Offset(0.3, 0.45), Offset(0.7, 0.45), Offset(0.4, 0.65),
      Offset(0.6, 0.65), Offset(0.5, 0.8),
    ];
    return positions
        .map((p) => Positioned(
              left: p.dx * 160 + 10,
              top: p.dy * 200 + 10,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ))
        .toList();
  }
}

class _Corner extends StatelessWidget {
  final Color color;
  final double size;
  final double thickness;
  final bool topLeft, topRight, bottomLeft, bottomRight;

  const _Corner({
    required this.color,
    required this.size,
    required this.thickness,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CornerPainter(
            color: color,
            thickness: thickness,
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight,
          ),
        ),
      );
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool topLeft, topRight, bottomLeft, bottomRight;

  _CornerPainter({
    required this.color,
    required this.thickness,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (topLeft) {
      canvas.drawLine(Offset(0, size.height), Offset.zero, paint);
      canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
    }
    if (bottomRight) {
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
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
  const _LiveBadge({required this.dotController});

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
          const Text(
            '● CANLI',
            style: TextStyle(
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.green : AppColors.bgCard2,
          borderRadius: BorderRadius.circular(10),
          border: isPrimary
              ? null
              : Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
  final List<double> poseLandmarks; // 33 × 4 (x, y, z, visibility)
  final List<double>? lhLandmarks;  // 21 × 3 (x, y, z)
  final List<double>? rhLandmarks;  // 21 × 3 (x, y, z)

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

    // Vücut iskeletini çiz
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

    // El iskeletini çiz
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

class _OnDeviceStatusBadge extends StatelessWidget {
  final bool ready;
  const _OnDeviceStatusBadge({required this.ready});

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppColors.green : const Color(0xFFE5A500);
    final label = ready ? 'On-Device ✓' : 'On-Device…';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w700,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.green : AppColors.bgCard2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.green : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.white : AppColors.textSub,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
