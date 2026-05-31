import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  bool _isInitialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('Hiç kamera bulunamadı');

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    _isInitialized = true;
  }

  /// JPEG baytı döner — base64 encode etmek için hazır.
  Future<XFile> takePicture() async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Kamera henüz hazır değil');
    }
    return _controller!.takePicture();
  }

  void dispose() {
    _controller?.dispose();
    _isInitialized = false;
  }
}
