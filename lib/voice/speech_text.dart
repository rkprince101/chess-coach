// Turns coach text into something a speech engine reads well: chess
// notation becomes words, evaluations become "plus one point three", and
// markdown leftovers disappear.

const _pieceNames = {'K': 'king', 'Q': 'queen', 'R': 'rook', 'B': 'bishop', 'N': 'knight'};

String _square(String sq) => '${sq[0]} ${sq[1]}';

String _suffix(String? s) => switch (s) {
      '+' => ' check',
      '#' => ' checkmate',
      _ => '',
    };

String normalizeForSpeech(String text) {
  var t = text;

  // Mate scores like #3 or #-2 (before markdown stripping eats the hash).
  t = t.replaceAllMapped(RegExp(r'(?<![\w#])#(-?)(\d+)\b'), (m) {
    return m[1] == '-' ? 'mate in ${m[2]} against' : 'mate in ${m[2]}';
  });

  // Evaluations: +1.35, -0.80, +0.00.
  t = t.replaceAllMapped(RegExp(r'(?<![\w.])([+-])(\d+)\.(\d+)'), (m) {
    final sign = m[1] == '+' ? 'plus' : 'minus';
    final whole = m[2]!;
    final frac = m[3]!.replaceAll(RegExp(r'0+$'), '');
    return frac.isEmpty ? '$sign $whole' : '$sign $whole point ${frac.split('').join(' ')}';
  });

  // Move numbers: "12." / "12..." before a move.
  t = t.replaceAll(RegExp(r'\b\d+\.{1,3}(?=\s*[KQRBNOa-h])'), '');

  // Castling.
  t = t.replaceAllMapped(RegExp(r'\bO-O-O([+#]?)'), (m) => 'castles queenside${_suffix(m[1])}');
  t = t.replaceAllMapped(RegExp(r'\bO-O([+#]?)'), (m) => 'castles kingside${_suffix(m[1])}');

  // Piece moves: Nf3, Nxe5, Bxf7+, R1e2, Nbd7, Qh5#.
  t = t.replaceAllMapped(
    RegExp(r'\b([KQRBN])([a-h]?[1-8]?)(x?)([a-h][1-8])(?:=([QRBN]))?([+#]?)(?![\w])'),
    (m) {
      final piece = _pieceNames[m[1]]!;
      final from = m[2]!.isEmpty ? '' : ' from ${m[2]!.split('').join(' ')}';
      final verb = m[3] == 'x' ? 'takes' : 'to';
      return '$piece$from $verb ${_square(m[4]!)}${_suffix(m[6])}';
    },
  );

  // Pawn captures and promotions: exd5, e8=Q+, exd8=N#.
  t = t.replaceAllMapped(
    RegExp(r'\b([a-h])x([a-h][1-8])(?:=([QRBN]))?([+#]?)(?![\w])'),
    (m) {
      final promo = m[3] == null ? '' : ', promoting to a ${_pieceNames[m[3]]}';
      return '${m[1]} pawn takes ${_square(m[2]!)}$promo${_suffix(m[4])}';
    },
  );
  t = t.replaceAllMapped(
    RegExp(r'\b([a-h][1-8])=([QRBN])([+#]?)(?![\w])'),
    (m) => 'pawn to ${_square(m[1]!)}, promoting to a ${_pieceNames[m[2]]}${_suffix(m[3])}',
  );

  // Bare squares: e4 -> "e 4" so engines say "e four", not "ee-four" or "e4".
  t = t.replaceAllMapped(RegExp(r'\b([a-h])([1-8])\b'), (m) => '${m[1]} ${m[2]}');

  // Markdown and symbols that read badly.
  t = t.replaceAll(RegExp(r'[*_`>|]'), '');
  t = t.replaceAll('→', ' to ').replaceAll('·', ',').replaceAll('—', ', ').replaceAll('–', ', ');
  t = t.replaceAll('%', ' percent');

  return t.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\s*\n\s*'), '\n').trim();
}

/// Accumulates streamed text and hands out complete sentences as soon as
/// they end, so speech can start before the model finishes writing.
class SentenceBuffer {
  final StringBuffer _pending = StringBuffer();

  static final _boundary = RegExp(r'(?<=[.!?:])["”)\]]?\s+(?=[A-Z0-9"“(])|\n+');

  /// Feeds a chunk and returns any sentences that are now complete.
  List<String> feed(String chunk) {
    _pending.write(chunk);
    final text = _pending.toString();
    final matches = _boundary.allMatches(text).toList();
    if (matches.isEmpty) return const [];
    final out = <String>[];
    var start = 0;
    for (final m in matches) {
      final sentence = text.substring(start, m.start + (m.group(0)!.startsWith('\n') ? 0 : 1)).trim();
      if (sentence.isNotEmpty) out.add(sentence);
      start = m.end;
    }
    _pending
      ..clear()
      ..write(text.substring(start));
    return out;
  }

  /// Returns whatever is left (call when the stream ends).
  String flush() {
    final rest = _pending.toString().trim();
    _pending.clear();
    return rest;
  }
}
