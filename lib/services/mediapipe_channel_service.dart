import 'package:flutter/services.dart';

/// Flutter ↔ Swift köprüsü: MediaPipe HolisticLandmarker
///
/// Swift tarafı (MediaPipePlugin.swift) şu metodları implemente eder:
///   initialize   → holistic_landmarker.task'ı yükler
///   extractKeypoints(frame: String) → 1692-dim float listesi döner
class MediaPipeChannelService {
  static const _channel = MethodChannel('sign.language.mediapipe');

  bool _initialized = false;
  bool get isReady => _initialized;

  Future<void> initialize() async {
    await _channel.invokeMethod<void>('initialize');
    _initialized = true;
  }

  /// [base64Frame]: Kameradan gelen tek JPEG kare (base64 string).
  /// Dönüş: 1692-dim keypoint vektörü veya null (el/vücut yoksa).
  Future<List<double>?> extractKeypoints(String base64Frame) async {
    if (!_initialized) return null;
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'extractKeypoints',
        {'frame': base64Frame},
      );
      if (result == null) return null;
      return result.map((v) => (v as num).toDouble()).toList();
    } on PlatformException catch (_) {
      return null;
    }
  }
}
