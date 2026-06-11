import 'package:flutter/material.dart';

class LanguageNotifier extends ChangeNotifier {
  String _language = 'en';
  String get language => _language;
  bool get isTurkish => _language == 'tr';

  void setLanguage(String lang) {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
  }
}
