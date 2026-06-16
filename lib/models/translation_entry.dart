enum TranslationType { TSID, TID }

class TranslationEntry {
  final String id;
  final String text;
  final TranslationType type;
  final DateTime createdAt;
  final String? translatedText;
  final String? targetLang;

  const TranslationEntry({
    required this.id,
    required this.text,
    required this.type,
    required this.createdAt,
    this.translatedText,
    this.targetLang,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'type': type.name,
    'createdAt': createdAt.toIso8601String(),
    if (translatedText != null) 'translatedText': translatedText,
    if (targetLang != null) 'targetLang': targetLang,
  };

  factory TranslationEntry.fromJson(Map<String, dynamic> json) => TranslationEntry(
    id: json['id'] as String,
    text: json['text'] as String,
    type: TranslationType.values.firstWhere((e) => e.name == json['type']),
    createdAt: DateTime.parse(json['createdAt'] as String),
    translatedText: json['translatedText'] as String?,
    targetLang: json['targetLang'] as String?,
  );
}
