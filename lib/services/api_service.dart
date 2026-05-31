import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prediction_result.dart';

class ApiService {
  // Platform başına varsayılan adresler:
  //   Android emülatör → 10.0.2.2:8000
  //   iOS simülatör    → localhost:8000
  //   Gerçek cihaz     → bilgisayarın LAN IP'si (ör. 192.168.1.x:8000)
  static const _urlKey = 'backend_url';
  static const _defaultUrl = 'http://10.0.2.2:8000';

  static String _baseUrl = _defaultUrl;
  static String get baseUrl => _baseUrl;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// main() içinde bir kez çağrılır — kaydedilmiş URL'i yükler.
  static Future<void> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_urlKey) ?? _defaultUrl;
  }

  /// Settings'ten URL değiştirmek için kullanılır.
  static Future<void> saveUrl(String url) async {
    _baseUrl = url.trimRight().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, _baseUrl);
  }

  Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 30 adet base64 JPEG frame gönderir, tahmin döner.
  Future<PredictionResult?> predict(
    List<String> base64Frames, {
    String language = 'tr',
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'frames': base64Frames, 'language': language}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return PredictionResult.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  /// Kelime listesinden akıcı cümle üretir (Ollama/Qwen).
  Future<String?> constructSentence(
    List<String> words, {
    String language = 'tr',
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/sentence'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'words': words, 'language': language}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['sentence'] as String?;
      }
    } catch (_) {}
    return null;
  }
}
