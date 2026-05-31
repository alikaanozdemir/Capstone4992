import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/prediction_result.dart';

class ApiService {
  // Android emulator → host machine: 10.0.2.2
  // iOS simulator  → host machine: localhost
  // Gerçek cihaz  → bilgisayarın LAN IP'si (ör. 192.168.1.x)
  static String baseUrl = 'http://10.0.2.2:8000';

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
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
            Uri.parse('$baseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'frames': base64Frames, 'language': language}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['word'] != null) {
          return PredictionResult.fromJson(data);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Kelime listesinden akıcı cümle üretir.
  Future<String?> constructSentence(
    List<String> words, {
    String language = 'tr',
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/sentence'),
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
