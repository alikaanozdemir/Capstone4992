class PredictionResult {
  final String word;
  final double confidence;

  const PredictionResult({required this.word, required this.confidence});

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      word: json['word'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}
