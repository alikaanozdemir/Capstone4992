import 'package:flutter/services.dart';

/// Tek bir kameradan gelen ham görüntü karesi.
///
/// Android: YUV420 (3 plane — Y, U, V; [bytesPerPixel] = piksel adımı).
/// iOS: BGRA8888 (1 plane; [bytesPerPixel] kullanılmaz).
class CameraFrame {
  final int width;
  final int height;

  /// Görüntüyü dik (upright) hale getirmek için saat yönünde döndürme açısı (0/90/180/270).
  final int rotationDegrees;

  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;

  const CameraFrame({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });
}

/// Flutter ↔ native köprüsü: MediaPipe HolisticLandmarker
///
/// Native taraf (MediaPipePlugin.swift / MediaPipePlugin.kt) şu metodları implemente eder:
///   initialize                → holistic_landmarker.task'ı yükler
///   extractKeypoints(frame)    → 1692-dim float listesi döner
class MediaPipeChannelService {
  static const _channel = MethodChannel('sign.language.mediapipe');

  bool _initialized = false;
  bool get isReady => _initialized;

  Future<void> initialize() async {
    await _channel.invokeMethod<void>('initialize');
    _initialized = true;
  }

  /// [frame]: kameradan gelen ham görüntü karesi.
  /// Dönüş: 1692-dim keypoint vektörü veya null (el/vücut yoksa).
  Future<List<double>?> extractKeypoints(CameraFrame frame) async {
    if (!_initialized) return null;
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'extractKeypoints',
        {
          'width': frame.width,
          'height': frame.height,
          'rotation': frame.rotationDegrees,
          'planes': frame.planes,
          'bytesPerRow': frame.bytesPerRow,
          'bytesPerPixel': frame.bytesPerPixel,
        },
      );
      if (result == null) return null;
      return result.map((v) => (v as num).toDouble()).toList();
    } on PlatformException catch (_) {
      return null;
    }
  }
}
