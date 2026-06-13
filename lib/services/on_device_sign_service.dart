import 'dart:async';
import 'package:flutter/foundation.dart';
import 'mediapipe_channel_service.dart';
import 'sign_recognizer_service.dart';

/// Bir frame geldiğinde dönen sonuç.
class FrameResult {
  final String? word;           // tanınan kelime (null = henüz yok)
  final double confidence;
  final List<double>? poseLm;   // 33×4 — görselleştirme için
  final List<double>? lhLm;    // 21×3
  final List<double>? rhLm;    // 21×3

  const FrameResult({
    this.word,
    this.confidence = 0.0,
    this.poseLm,
    this.lhLm,
    this.rhLm,
  });
}

/// Tam on-device işaret tanıma pipeline'ı.
///
/// Her frame için:
///   1. MediaPipe → 1692-dim keypoints (Swift native)
///   2. Gate 1: Frame'lerin ≥%50'sinde el var mı?
///   3. Gate 2: Yeterli hareket var mı?
///   4. ONNX → sınıf + güven skoru
///   5. Momentum filtresi (aynı etiket MOMENTUM kez üst üste gelmeli)
class OnDeviceSignService {
  /// Üretimde kapatılabilir benchmark log flag'i — [BENCH] satırları bu bayrağa bağlı.
  static const bool kBenchmark = true;

  final _mp = MediaPipeChannelService();
  final _ort = SignRecognizerService();

  // Keypoint tamponu (30 kare, 1692 dim her biri)
  final _kpBuf = <List<double>>[];
  static const _bufSize = 30;

  // Gate sabitleri
  static const double _minHandRatio = 0.5;   // son 15 frame'in yarısında el
  static const double _minMotion   = 0.003;   // el hareketi std eşiği

  // Momentum filtresi (Python: MOMENTUM=2)
  static const int _momentum = 2;
  String? _pending;
  int _streak = 0;
  String? _lastEmit;

  // Tanı amaçlı: durum geçişlerini bir kez logla (her frame'de spam yapmamak için)
  bool? _lastExtractOk;
  bool? _lastGatesPassed;

  bool get isReady => _mp.isReady && _ort.isReady;

  Future<void> initialize(String language) async {
    await _mp.initialize();
    await _ort.initialize(language);
    _reset();
  }

  void _reset() {
    _kpBuf.clear();
    _pending = null;
    _streak = 0;
    _lastEmit = null;
    _lastExtractOk = null;
    _lastGatesPassed = null;
  }

  void resetBuffer() => _reset();

  // ── Gate yardımcıları ─────────────────────────────────────────────────────

  static const _faceEnd = 132 + 1434;  // 1566
  static const _lhEnd   = _faceEnd + 63; // 1629

  bool _hasHands(List<double> kp) {
    double sum = 0;
    for (int i = _faceEnd; i < kp.length; i++) {
      sum += kp[i].abs();
    }
    return sum > 0.05;
  }

  bool _hasMotion(List<List<double>> buf) {
    if (buf.length < 10) return false;
    final n = buf.length;
    final cols = buf[0].length - _faceEnd; // el koordinatı sayısı
    double totalVariance = 0;
    for (int j = _faceEnd; j < buf[0].length; j++) {
      double mean = 0;
      for (final frame in buf) {
        mean += frame[j];
      }
      mean /= n;
      double variance = 0;
      for (final frame in buf) {
        final diff = frame[j] - mean;
        variance += diff * diff;
      }
      totalVariance += variance / n;
    }
    // Ortalama varyans — sqrt almadan eşikle karşılaştır (eşik de karesi alınmış)
    return (totalVariance / cols) > (_minMotion * _minMotion);
  }

  // Landmark vektörünü görselleştirme için parçala
  static Map<String, List<double>> _splitForViz(List<double> kp) {
    return {
      'pose': kp.sublist(0, 132),
      'lh':   kp.sublist(_faceEnd, _lhEnd),
      'rh':   kp.sublist(_lhEnd),
    };
  }

  // ── Ana işlem döngüsü ─────────────────────────────────────────────────────

  /// Her kamera frame'i için çağrılır.
  /// [frame]: kameradan gelen ham görüntü karesi (YUV420/BGRA8888).
  /// Dönüş: FrameResult (word null olabilir — sadece kp güncellemesi).
  Future<FrameResult> processFrame(CameraFrame frame) async {
    // 1. Keypoints çıkar
    Stopwatch? mpWatch;
    if (kBenchmark) mpWatch = Stopwatch()..start();
    final kp = await _mp.extractKeypoints(frame);
    if (kBenchmark) {
      mpWatch!.stop();
      debugPrint('[BENCH] mediapipe: ${mpWatch.elapsedMilliseconds} ms');
    }
    final extractOk = kp != null && kp.length == SignRecognizerService.featureDim;
    if (extractOk != _lastExtractOk) {
      _lastExtractOk = extractOk;
      debugPrint(extractOk
          ? '[OnDevice] MediaPipe keypoints OK (len=${kp.length})'
          : '[OnDevice] MediaPipe keypoints NULL/invalid (len=${kp?.length})');
    }
    if (!extractOk) {
      return const FrameResult();
    }

    _kpBuf.add(kp);
    if (_kpBuf.length > _bufSize) _kpBuf.removeAt(0);

    final viz = _splitForViz(kp);
    final poseLm = viz['pose'];
    final lhLm   = viz['lh'];
    final rhLm   = viz['rh'];

    if (_kpBuf.length < _bufSize) {
      return FrameResult(poseLm: poseLm, lhLm: lhLm, rhLm: rhLm);
    }

    // 2. Gate 1: Son 15 frame'in yarısında el olmalı
    final recent = _kpBuf.sublist(_kpBuf.length - 15);
    final handFrames = recent.where(_hasHands).length;
    if (handFrames < recent.length * _minHandRatio) {
      if (_lastGatesPassed != false) {
        _lastGatesPassed = false;
        debugPrint('[OnDevice] Gate1 FAIL: hand frames $handFrames/${recent.length}');
      }
      _pending = null;
      _streak = 0;
      return FrameResult(poseLm: poseLm, lhLm: lhLm, rhLm: rhLm);
    }

    // 3. Gate 2: Yeterli hareket
    if (!_hasMotion(_kpBuf)) {
      if (_lastGatesPassed != false) {
        _lastGatesPassed = false;
        debugPrint('[OnDevice] Gate2 FAIL: not enough motion');
      }
      _pending = null;
      _streak = 0;
      return FrameResult(poseLm: poseLm, lhLm: lhLm, rhLm: rhLm);
    }

    if (_lastGatesPassed != true) {
      _lastGatesPassed = true;
      debugPrint('[OnDevice] Gates PASSED — running ONNX inference');
    }

    // 4. ONNX inference
    Stopwatch? inferWatch;
    if (kBenchmark) inferWatch = Stopwatch()..start();
    final prediction = await _ort.predict(_kpBuf);
    if (kBenchmark) {
      inferWatch!.stop();
      debugPrint('[BENCH] inference: ${inferWatch.elapsedMilliseconds} ms');
    }
    if (prediction == null) {
      return FrameResult(poseLm: poseLm, lhLm: lhLm, rhLm: rhLm);
    }

    final (label, conf) = prediction;
    debugPrint('[OnDevice] prediction: $label (${(conf * 100).toStringAsFixed(1)}%)');

    // 5. Güven eşiği
    const confThresh = 0.35;
    if (conf < confThresh) {
      _pending = null;
      _streak = 0;
      return FrameResult(confidence: conf, poseLm: poseLm, lhLm: lhLm, rhLm: rhLm);
    }

    // 6. Momentum filtresi
    if (label == _pending) {
      _streak++;
    } else {
      _pending = label;
      _streak = 1;
    }

    if (_streak >= _momentum && label != _lastEmit) {
      _lastEmit = label;
      return FrameResult(
        word: label,
        confidence: conf,
        poseLm: poseLm,
        lhLm: lhLm,
        rhLm: rhLm,
      );
    }

    return FrameResult(confidence: conf, poseLm: poseLm, lhLm: lhLm, rhLm: rhLm);
  }

  void dispose() {
    _ort.dispose();
    _reset();
  }
}
