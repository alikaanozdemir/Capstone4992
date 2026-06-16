import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

/// SentencePiece Unigram tokenizer — MarianMT modellerinin Dart uygulaması.
///
/// Python tarafındaki `convert_nmt_to_onnx.py` tarafından üretilen vocab JSON
/// dosyasından yüklenir. Viterbi DP ile metni token ID listesine dönüştürür;
/// token ID listesini tekrar metne çevirir.
///
/// JSON formatı:
///   pieces: List<String>   (index = token id)
///   scores: List<double>   (SentencePiece log-prob)
///   eos_id, pad_id, unk_id, decoder_start_token_id
class NmtTokenizer {
  final List<String> _pieces;
  final List<double> _scores;
  final Map<String, int> _piece2id;
  final int _maxPieceLen;

  final int eosId;
  final int padId;
  final int unkId;
  final int decoderStartId;

  NmtTokenizer._({
    required List<String> pieces,
    required List<double> scores,
    required this.eosId,
    required this.padId,
    required this.unkId,
    required this.decoderStartId,
  })  : _pieces = pieces,
        _scores = scores,
        _piece2id = {for (int i = 0; i < pieces.length; i++) pieces[i]: i},
        _maxPieceLen = pieces.fold(0, (m, p) => max(m, p.runes.length));

  /// vocab JSON asset'inden yükle.
  /// [assetPath] → örn. `assets/models/nmt_tr_en_vocab.json`
  static Future<NmtTokenizer> fromAsset(String assetPath) async {
    final raw  = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;

    final pieces = (data['pieces'] as List).cast<String>();
    final scores = (data['scores'] as List)
        .map((v) => (v as num).toDouble())
        .toList();

    return NmtTokenizer._(
      pieces:          pieces,
      scores:          scores,
      eosId:           data['eos_id'] as int,
      padId:           data['pad_id'] as int,
      unkId:           data['unk_id'] as int,
      decoderStartId:  data['decoder_start_token_id'] as int,
    );
  }

  // ── Encoding ───────────────────────────────────────────────────────────────

  /// Metni token ID listesine çevirir (EOS dahil).
  ///
  /// Pipeline:
  ///   1. Boşlukları `▁` ile değiştir, başına `▁` ekle
  ///   2. Viterbi Unigram DP ile optimal bölümleme bul
  ///   3. EOS ekle
  List<int> encode(String text) {
    if (text.trim().isEmpty) return [eosId];

    // Normalize: kelime başlarını ▁ ile işaretle
    final normalized = '▁${text.trim().replaceAll(' ', '▁')}';
    final chars      = normalized.runes.toList();
    final n          = chars.length;

    // DP tablosu
    final bestScore   = List.filled(n + 1, double.negativeInfinity);
    final bestPiece   = List.filled(n + 1, -1);   // seçilen piece id
    final bestPrev    = List.filled(n + 1, -1);    // önceki pozisyon
    bestScore[0] = 0.0;

    for (int i = 0; i < n; i++) {
      if (bestScore[i] == double.negativeInfinity) continue;

      // Maksimum piece uzunluğu kadar karakter dene
      final maxJ = min(n, i + _maxPieceLen);
      for (int j = i + 1; j <= maxJ; j++) {
        final piece = String.fromCharCodes(chars.sublist(i, j));
        final id    = _piece2id[piece];
        if (id == null) continue;
        final score = bestScore[i] + _scores[id];
        if (score > bestScore[j]) {
          bestScore[j]  = score;
          bestPiece[j]  = id;
          bestPrev[j]   = i;
        }
      }

      // Bilinmeyen karakter: unk_id ile tek karakterlik atlama
      if (bestScore[i + 1] == double.negativeInfinity) {
        bestScore[i + 1] = bestScore[i] - 100.0; // düşük skor
        bestPiece[i + 1] = unkId;
        bestPrev[i + 1]  = i;
      }
    }

    // Geriye iz sür
    final reversed = <int>[];
    int pos = n;
    while (pos > 0) {
      reversed.add(bestPiece[pos]);
      pos = bestPrev[pos];
    }
    return [...reversed.reversed, eosId];
  }

  // ── Decoding ───────────────────────────────────────────────────────────────

  /// Token ID listesini metne çevirir.
  ///
  /// EOS / PAD / UNK tokenları atlanır.
  /// `▁` → boşluk dönüşümü uygulanır.
  String decode(List<int> ids) {
    final skip = {eosId, padId, unkId};
    final buf  = StringBuffer();
    for (final id in ids) {
      if (id < 0 || id >= _pieces.length) continue;
      if (skip.contains(id)) continue;
      final piece = _pieces[id];
      if (piece.startsWith('▁')) {
        // ▁ = boşluk + sonraki harf
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(piece.substring(1));   // ▁ karakterini çıkar
      } else {
        buf.write(piece);
      }
    }
    final result = buf.toString().trim();
    // Baş harfini büyüt
    if (result.isEmpty) return result;
    return result[0].toUpperCase() + result.substring(1);
  }

  /// Attention mask üret: token ID'leri için 1, pad için 0.
  List<int> attentionMask(List<int> ids) =>
      ids.map((id) => id == padId ? 0 : 1).toList();
}
