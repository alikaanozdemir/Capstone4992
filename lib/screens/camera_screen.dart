import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/camera_service.dart';
import '../services/api_service.dart';

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

  // ── Durum ─────────────────────────────────────────────────────────────────
  bool _camReady = false;
  bool _backendUp = false;
  String _statusMsg = 'Başlatılıyor...';

  // Tanıma çıktısı
  String _sentence = '';
  final _words = <String>[];
  double _confidence = 0.0;
  bool _thinking = false;

  // Frame tamponu
  final List<String> _frameBuf = [];
  static const int _bufSize = 30;
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
    // Backend bağlantı kontrolü
    final up = await _api.checkHealth();
    if (mounted) setState(() => _backendUp = up);

    // Kamerayı aç
    try {
      await _cam.initialize();
      if (mounted) {
        setState(() {
          _camReady = true;
          _statusMsg = up ? 'Hazır — işaret yapın' : 'Backend bağlantısı yok';
        });
        _startCapture();
      }
    } catch (e) {
      if (mounted) setState(() => _statusMsg = 'Kamera hatası: $e');
    }
  }

  // ── Frame yakalama ────────────────────────────────────────────────────────

  void _startCapture() {
    // Her 500ms'de bir fotoğraf çek → 30 karelik tampon dolunca backend'e gönder
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _captureFrame(),
    );
  }

  Future<void> _captureFrame() async {
    if (_capturing || !_camReady || !_backendUp) return;
    _capturing = true;
    try {
      final file = await _cam.takePicture();
      final bytes = await file.readAsBytes();
      _frameBuf.add(base64Encode(bytes));
      if (_frameBuf.length > _bufSize) _frameBuf.removeAt(0);
      if (_frameBuf.length >= _bufSize) _sendBuffer();
    } catch (_) {
    } finally {
      _capturing = false;
    }
  }

  Future<void> _sendBuffer() async {
    final frames = List<String>.from(_frameBuf);
    final result = await _api.predict(frames);
    if (!mounted || result == null) return;

    setState(() {
      _confidence = result.confidence;
      if (!_words.contains(result.word)) {
        _words.add(result.word);
        if (_words.length > 6) _words.removeAt(0);
      }
    });
    _resetSilence();
  }

  void _resetSilence() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silence, _buildSentence);
  }

  Future<void> _buildSentence() async {
    if (_words.isEmpty) return;
    setState(() => _thinking = true);
    final ws = List<String>.from(_words);
    final s = await _api.constructSentence(ws);
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
    setState(() {
      _sentence = '';
      _words.clear();
      _frameBuf.clear();
      _confidence = 0;
      _thinking = false;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotController.dispose();
    _captureTimer?.cancel();
    _silenceTimer?.cancel();
    _cam.dispose();
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

                          // El algılama kutusu (kamera hazır olunca)
                          if (_camReady)
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

                          // Alt sol — CANLI + backend durumu
                          if (_camReady)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              child: Row(
                                children: [
                                  _LiveBadge(dotController: _dotController),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _backendUp
                                          ? 'Backend bağlı'
                                          : 'Backend yok',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _backendUp
                                            ? AppColors.green
                                            : const Color(0xFFE74C3C),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
