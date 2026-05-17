enum TranslationType { TSID, TID }

class TranslationEntry {
  final String id;
  final String text;
  final TranslationType type;
  final DateTime createdAt;

  const TranslationEntry({
    required this.id,
    required this.text,
    required this.type,
    required this.createdAt,
  });
}

final List<TranslationEntry> mockHistory = [
  TranslationEntry(
    id: '1',
    text: 'Merhaba, ben doktorunuzum.',
    type: TranslationType.TSID,
    createdAt: DateTime.now().subtract(const Duration(minutes: 21)),
  ),
  TranslationEntry(
    id: '2',
    text: 'Su içmek istiyorum, yardımcı olur musunuz?',
    type: TranslationType.TID,
    createdAt: DateTime.now().subtract(const Duration(minutes: 58)),
  ),
  TranslationEntry(
    id: '3',
    text: 'Başım çok ağrıyor, ilaç alabilir miyim?',
    type: TranslationType.TSID,
    createdAt: DateTime.now().subtract(const Duration(hours: 7, minutes: 44)),
  ),
  TranslationEntry(
    id: '4',
    text: 'Lütfen yavaş konuşun, anlamıyorum.',
    type: TranslationType.TID,
    createdAt: DateTime.now().subtract(const Duration(hours: 7, minutes: 58)),
  ),
  TranslationEntry(
    id: '5',
    text: 'Ameliyat öncesi hazırlık gerekiyor mu?',
    type: TranslationType.TSID,
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
  ),
  TranslationEntry(
    id: '6',
    text: 'Ağrı kesici almak istiyorum.',
    type: TranslationType.TID,
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 5)),
  ),
];
