import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// ONNX model inference service — PyTorch modelin Dart karşılığı.
///
/// Preprocessing Python kodunun birebir çevirisi:
///   per_seq_center → _perSeqCenter
///   standardize    → _standardize
class SignRecognizerService {
  OrtSession? _session;
  List<String> _labels = [];
  List<double>? _featMean;
  List<double>? _featStd;
  bool _initialized = false;

  static const int seqLen = 30;
  static const int featureDim = 1692;

  String _activeProvider = 'CPU';

  bool get isReady => _initialized;
  List<String> get labels => _labels;

  /// Aktif donanım hızlandırma execution provider'ı (CoreML/NNAPI/CPU) — debug overlay için.
  String get activeProvider => _activeProvider;

  Future<void> initialize(String language) async {
    final dataset = language == 'tr' ? 'autsl' : 'asl_citizen';

    OrtEnv.instance.init();

    // Model bytes'ı asset'ten yükle
    final modelData = await rootBundle.load('assets/models/model_$dataset.onnx');
    final opts = _buildSessionOptions();
    _session = OrtSession.fromBuffer(modelData.buffer.asUint8List(), opts);

    // Preprocessing meta verisi
    final metaStr = await rootBundle.loadString('assets/models/preprocess_$dataset.json');
    final meta = jsonDecode(metaStr) as Map<String, dynamic>;

    _labels = (meta['labels'] as List).cast<String>();

    final meanRaw = meta['feat_mean'] as List?;
    final stdRaw  = meta['feat_std']  as List?;
    if (meanRaw != null && stdRaw != null) {
      _featMean = meanRaw.map((v) => (v as num).toDouble()).toList();
      _featStd  = stdRaw.map((v) => (v as num).toDouble()).toList();
    }

    _initialized = true;
  }

  /// Platforma göre donanım hızlandırma execution provider'larını ekler.
  /// Desteklenmeyen op'lar (MatMulInteger, DynamicQuantizeLSTM) otomatik
  /// olarak CPU'ya düşer — XNNPACK/CPU her zaman fallback olarak eklenir.
  OrtSessionOptions _buildSessionOptions() {
    final opts = OrtSessionOptions();
    try {
      if (Platform.isAndroid) {
        opts.appendNnapiProvider(NnapiFlags.useNone);    // NPU/GPU/DSP
        _activeProvider = 'NNAPI';
      } else if (Platform.isIOS) {
        opts.appendCoreMLProvider(CoreMLFlags.useNone);  // Apple Neural Engine
        _activeProvider = 'CoreML';
      }
    } catch (e) {
      debugPrint('[ORT] donanım delegate eklenemedi, CPU fallback: $e');
      _activeProvider = 'CPU';
    }
    try { opts.appendXnnpackProvider(); } catch (_) {}   // optimize CPU
    try { opts.appendCPUProvider(CPUFlags.useNone); } catch (_) {}
    return opts;
  }

  // ── Preprocessing ─────────────────────────────────────────────────────────

  /// Python: per_seq_center — sıfır olmayan kareleri kendi ortalamaları etrafında merkeze al.
  List<List<double>> _perSeqCenter(List<List<double>> seq) {
    final result = seq.map((f) => List<double>.from(f)).toList();

    final nonZeroIdx = <int>[];
    for (int i = 0; i < result.length; i++) {
      double sum = 0;
      for (final v in result[i]) {
        sum += v.abs();
      }
      if (sum > 1e-6) nonZeroIdx.add(i);
    }
    if (nonZeroIdx.isEmpty) return result;

    // Ortalama hesapla
    final mean = List<double>.filled(featureDim, 0.0);
    for (final i in nonZeroIdx) {
      for (int j = 0; j < featureDim; j++) {
        mean[j] += result[i][j];
      }
    }
    final n = nonZeroIdx.length.toDouble();
    for (int j = 0; j < featureDim; j++) {
      mean[j] /= n;
    }

    // Ortalamayı çıkar
    for (final i in nonZeroIdx) {
      for (int j = 0; j < featureDim; j++) {
        result[i][j] -= mean[j];
      }
    }
    return result;
  }

  /// Python: standardize — sıfır olmayan kareleri feat_mean/feat_std ile normalize et.
  void _standardize(List<List<double>> seq) {
    if (_featMean == null || _featStd == null) return;
    for (final frame in seq) {
      double absSum = 0;
      for (final v in frame) {
        absSum += v.abs();
      }
      if (absSum <= 1e-6) continue; // sıfır kare olduğu gibi kalır
      for (int j = 0; j < featureDim; j++) {
        frame[j] = (frame[j] - _featMean![j]) / _featStd![j];
      }
    }
  }

  List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(max);
    final exps = logits.map((v) => exp(v - maxVal)).toList();
    final sum = exps.fold(0.0, (a, b) => a + b);
    return exps.map((v) => v / sum).toList();
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Bir sekans üzerinde tahmin yapar.
  /// [keypointBuffer]: her eleman 1692-dim float vektör (MediaPipe keypoints).
  /// Dönüş: (etiket, güven) veya null (buffer yetersizse veya model hazır değilse).
  Future<(String, double)?> predict(List<List<double>> keypointBuffer) async {
    if (!_initialized || _session == null) return null;
    if (keypointBuffer.length < seqLen) return null;

    // Son seqLen kareyi al
    final seq = keypointBuffer.sublist(keypointBuffer.length - seqLen);

    // Preprocessing
    final centered = _perSeqCenter(seq);
    _standardize(centered);

    // Float32 flatten: [1, 30, 1692]
    final flat = Float32List(seqLen * featureDim);
    for (int i = 0; i < seqLen; i++) {
      for (int j = 0; j < featureDim; j++) {
        flat[i * featureDim + j] = centered[i][j];
      }
    }

    // ONNX inference
    final tensor = OrtValueTensor.createTensorWithDataList(flat, [1, seqLen, featureDim]);
    final runOptions = OrtRunOptions();

    List<OrtValue?>? outputs;
    try {
      outputs = await _session!.runAsync(runOptions, {'keypoints': tensor});
    } finally {
      tensor.release();
      runOptions.release();
    }

    if (outputs == null || outputs.isEmpty || outputs[0] == null) return null;

    final rawValue = outputs[0]!.value;
    outputs[0]!.release();

    // Çıktı şekli [1, n_classes] — iç listeyi al
    final logits = (rawValue as List<List<double>>)[0];
    final probs = _softmax(logits);

    int maxIdx = 0;
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > probs[maxIdx]) maxIdx = i;
    }

    return (_labels[maxIdx], probs[maxIdx]);
  }

  void dispose() {
    _session?.release();
    _session = null;
    _initialized = false;
    OrtEnv.instance.release();
  }
}
