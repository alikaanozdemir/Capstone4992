import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'nmt_tokenizer.dart';

/// On-device NMT çeviri servisi — ağ bağlantısı gerektirmez.
///
/// sign_recognizer_service.dart ile aynı ONNX Runtime altyapısını kullanır.
/// `convert_nmt_to_onnx.py` tarafından üretilen kantize edilmiş modelleri yükler.
///
/// Desteklenen çeviriler:
///   tr → en   (nmt_tr_en_{encoder,decoder}.onnx)
///   en → fr   (nmt_en_fr_{encoder,decoder}.onnx)
///   tr → fr   (tr→en→fr zinciri, iki adımlı)
///
/// Kullanım:
///   final nmt = NmtService();
///   await nmt.initialize();
///   final fr = await nmt.translate('Ben eve gidiyorum.', source: 'tr', target: 'fr');
class NmtService {
  _NmtPair? _trEn;
  _NmtPair? _enFr;
  bool _initialized = false;

  bool get isReady => _initialized;

  /// Her iki çeviri çiftini yükler. Modeller yoksa gracefully hata yapar.
  Future<void> initialize() async {
    OrtEnv.instance.init();
    try {
      _trEn = await _NmtPair.load(
        encoderAsset: 'assets/models/nmt_tr_en_encoder.onnx',
        decoderAsset: 'assets/models/nmt_tr_en_decoder.onnx',
        vocabAsset:   'assets/models/nmt_tr_en_vocab.json',
      );
      debugPrint('[NMT] tr→en hazır');
    } catch (e) {
      debugPrint('[NMT] tr→en yüklenemedi: $e');
    }
    try {
      _enFr = await _NmtPair.load(
        encoderAsset: 'assets/models/nmt_en_fr_encoder.onnx',
        decoderAsset: 'assets/models/nmt_en_fr_decoder.onnx',
        vocabAsset:   'assets/models/nmt_en_fr_vocab.json',
      );
      debugPrint('[NMT] en→fr hazır');
    } catch (e) {
      debugPrint('[NMT] en→fr yüklenemedi: $e');
    }
    _initialized = _trEn != null || _enFr != null;
  }

  /// Metni hedef dile çevirir.
  ///
  /// tr→fr: iki adımlı zincir (tr→en→fr).
  /// Model yüklü değilse null döner.
  Future<String?> translate(
    String text, {
    required String source,
    required String target,
  }) async {
    if (text.trim().isEmpty || source == target) return null;

    try {
      if (source == 'tr' && target == 'en') {
        return await _trEn?.translate(text);
      }
      if (source == 'en' && target == 'fr') {
        return await _enFr?.translate(text);
      }
      if (source == 'tr' && target == 'fr') {
        // İki adım: Türkçe → İngilizce → Fransızca
        final en = await _trEn?.translate(text);
        if (en == null || en.isEmpty) return null;
        return await _enFr?.translate(en);
      }
    } catch (e, st) {
      debugPrint('[NMT] Çeviri hatası: $e\n$st');
    }
    return null;
  }

  void dispose() {
    _trEn?.dispose();
    _enFr?.dispose();
    _initialized = false;
    OrtEnv.instance.release();
  }
}

// ── İç yardımcı: tek bir çeviri çifti ────────────────────────────────────────

class _NmtPair {
  final OrtSession _encoder;
  final OrtSession _decoder;
  final NmtTokenizer _tokenizer;

  /// Greedy decode maksimum token sayısı
  static const int _maxNewTokens = 64;

  _NmtPair._(this._encoder, this._decoder, this._tokenizer);

  static Future<_NmtPair> load({
    required String encoderAsset,
    required String decoderAsset,
    required String vocabAsset,
  }) async {
    final opts = _sessionOptions();

    final encBytes = await rootBundle.load(encoderAsset);
    final decBytes = await rootBundle.load(decoderAsset);

    final encoder   = OrtSession.fromBuffer(encBytes.buffer.asUint8List(), opts);
    final decoder   = OrtSession.fromBuffer(decBytes.buffer.asUint8List(), opts);
    final tokenizer = await NmtTokenizer.fromAsset(vocabAsset);

    return _NmtPair._(encoder, decoder, tokenizer);
  }

  static OrtSessionOptions _sessionOptions() {
    final opts = OrtSessionOptions();
    try { opts.appendXnnpackProvider(); } catch (_) {}
    try { opts.appendCPUProvider(CPUFlags.useNone); } catch (_) {}
    return opts;
  }

  // ── Encoder ──────────────────────────────────────────────────────────────

  /// Kaynak metni encode eder.
  /// Dönüş: (encoder_hidden_states: Float32List, src_len: int, hidden_size: int)
  Future<({Float32List hidden, int srcLen, int hiddenSize})?> _encode(
    String text,
  ) async {
    final ids  = _tokenizer.encode(text);
    final mask = _tokenizer.attentionMask(ids);

    final inputIds   = Int64List.fromList(ids);
    final attnMask   = Int64List.fromList(mask);
    final inputTensor = OrtValueTensor.createTensorWithDataList(inputIds,  [1, ids.length]);
    final maskTensor  = OrtValueTensor.createTensorWithDataList(attnMask, [1, mask.length]);
    final runOpts     = OrtRunOptions();

    List<OrtValue?>? outputs;
    try {
      outputs = await _encoder.runAsync(runOpts, {
        'input_ids':      inputTensor,
        'attention_mask': maskTensor,
      });
    } finally {
      inputTensor.release();
      maskTensor.release();
      runOpts.release();
    }

    if (outputs == null || outputs.isEmpty || outputs[0] == null) return null;

    // Encoder output: [1, src_len, hidden_size] → Float32List
    final raw        = outputs[0]!.value as List<List<List<double>>>;
    final srcLen     = raw[0].length;
    final hiddenSize = raw[0][0].length;
    outputs[0]!.release();

    final hidden = Float32List(srcLen * hiddenSize);
    for (int i = 0; i < srcLen; i++) {
      for (int j = 0; j < hiddenSize; j++) {
        hidden[i * hiddenSize + j] = raw[0][i][j].toDouble();
      }
    }
    return (hidden: hidden, srcLen: srcLen, hiddenSize: hiddenSize);
  }

  // ── Greedy decoder ────────────────────────────────────────────────────────

  Future<List<int>?> _greedyDecode(
    Float32List hidden,
    int srcLen,
    int hiddenSize,
    Int64List encoderMask,
  ) async {
    final hiddenTensor = OrtValueTensor.createTensorWithDataList(
      hidden, [1, srcLen, hiddenSize],
    );

    final generated   = <int>[];
    var   decInput    = <int>[_tokenizer.decoderStartId];

    try {
      for (int step = 0; step < _maxNewTokens; step++) {
        final decIds    = Int64List.fromList(decInput);
        final decTensor = OrtValueTensor.createTensorWithDataList(decIds, [1, decInput.length]);
        final maskTensor = OrtValueTensor.createTensorWithDataList(encoderMask, [1, encoderMask.length]);
        final runOpts   = OrtRunOptions();

        List<OrtValue?>? outputs;
        try {
          outputs = await _decoder.runAsync(runOpts, {
            'input_ids':              decTensor,
            'encoder_hidden_states':  hiddenTensor,
            'encoder_attention_mask': maskTensor,
          });
        } finally {
          decTensor.release();
          maskTensor.release();
          runOpts.release();
        }

        if (outputs == null || outputs.isEmpty || outputs[0] == null) break;

        // Logits: [1, dec_len, vocab_size] — son token'ın logit'leri
        final logitsRaw = outputs[0]!.value as List<List<List<double>>>;
        final lastLogits = logitsRaw[0][decInput.length - 1]; // son pozisyon
        outputs[0]!.release();

        // Argmax
        int bestId = 0;
        double bestVal = lastLogits[0];
        for (int i = 1; i < lastLogits.length; i++) {
          if (lastLogits[i] > bestVal) {
            bestVal = lastLogits[i];
            bestId  = i;
          }
        }

        if (bestId == _tokenizer.eosId) break;
        generated.add(bestId);
        decInput = [...decInput, bestId];
      }
    } finally {
      hiddenTensor.release();
    }

    return generated.isEmpty ? null : generated;
  }

  // ── Public translate ──────────────────────────────────────────────────────

  Future<String?> translate(String text) async {
    if (text.trim().isEmpty) return null;

    final enc = await _encode(text);
    if (enc == null) return null;

    final srcIds = _tokenizer.encode(text);
    final mask   = Int64List.fromList(_tokenizer.attentionMask(srcIds));

    final tokenIds = await _greedyDecode(enc.hidden, enc.srcLen, enc.hiddenSize, mask);
    if (tokenIds == null) return null;

    return _tokenizer.decode(tokenIds);
  }

  void dispose() {
    _encoder.release();
    _decoder.release();
  }
}
