import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/translation_entry.dart';

class HistoryService {
  static const _key = 'translation_history';

  static Future<List<TranslationEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final entries = raw
        .map((e) => TranslationEntry.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    return entries.reversed.toList();
  }

  static Future<void> add(TranslationEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(entry.toJson()));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
