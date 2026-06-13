import 'dart:io' show Platform;
import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  bool _isInitialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;

  /// Görüntüyü dik (upright) hale getirmek için saat yönünde döndürme açısı.
  int get sensorOrientation => _controller?.description.sensorOrientation ?? 0;

  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('Hiç kamera bulunamadı');

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    await _controller!.initialize();
    _isInitialized = true;
  }

  /// Ham kamera kare akışını başlatır (Android: YUV420, iOS: BGRA8888).
  void startImageStream(void Function(CameraImage image) onFrame) {
    if (!_isInitialized || _controller == null) {
      throw Exception('Kamera henüz hazır değil');
    }
    _controller!.startImageStream(onFrame);
  }

  void dispose() {
    _controller?.dispose();
    _isInitialized = false;
  }
}
