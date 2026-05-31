class PredictionResult {
  final String? word;
  final double confidence;
  final List<double>? poseLandmarks; // 33 × 4 = 132 values (x, y, z, visibility)
  final List<double>? lhLandmarks;  // 21 × 3 = 63 values (x, y, z)
  final List<double>? rhLandmarks;  // 21 × 3 = 63 values (x, y, z)

  const PredictionResult({
    required this.word,
    required this.confidence,
    this.poseLandmarks,
    this.lhLandmarks,
    this.rhLandmarks,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    final kp = json['kp'] as Map<String, dynamic>?;
    return PredictionResult(
      word: json['word'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
      poseLandmarks: kp != null
          ? List<double>.from((kp['pose'] as List).map((v) => (v as num).toDouble()))
          : null,
      lhLandmarks: kp != null
          ? List<double>.from((kp['lh'] as List).map((v) => (v as num).toDouble()))
          : null,
      rhLandmarks: kp != null
          ? List<double>.from((kp['rh'] as List).map((v) => (v as num).toDouble()))
          : null,
    );
  }
}
