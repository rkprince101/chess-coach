import 'package:chess/engine/search.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult analyze(String fen, {int timeMs = 3000, int maxDepth = 5}) {
  final pos = Chess.fromSetup(Setup.parseFen(fen));
  return Searcher(timeLimitMs: timeMs, maxDepth: maxDepth).search(pos);
}

void main() {
  test('finds back-rank mate in one', () {
    // White: Kg1, Ra1; Black: Kg8, pawns f7 g7 h7. Ra8# mates.
    final r = analyze('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1');
    expect(r.bestMove!.uci, 'a1a8');
    expect(isMateScore(r.score), isTrue);
    expect(mateIn(r.score), 1);
  });

  test('captures a hanging queen', () {
    // Black queen on d5 attacked by white knight on c3, undefended.
    final r = analyze('4k3/8/8/3q4/8/2N5/8/4K3 w - - 0 1');
    expect(r.bestMove!.uci, 'c3d5');
  });

  test('avoids hanging its own queen', () {
    // White queen on d1; a rook on d8 eyes the d-file. Qd7?? would be captured.
    final r = analyze('3rk3/8/8/8/8/8/8/3QK3 w - - 0 1');
    final after = Chess.fromSetup(Setup.parseFen(r.fen)).play(r.bestMove!);
    // Queen must not be capturable for free on the next move.
    final queenSq = after.board.piecesOf(Side.white, Role.queen).first!;
    final attackers = after.board.attacksTo(queenSq, Side.black);
    final defenders = after.board.attacksTo(queenSq, Side.white);
    expect(attackers.isEmpty || defenders.isNotEmpty, isTrue,
        reason: 'engine hung its queen with ${r.bestMove!.uci}');
  });

  test('reaches a reasonable depth from the start position in a second', () {
    final r = analyze(kInitialFEN, timeMs: 1000, maxDepth: 6);
    // ignore: avoid_print
    print('depth ${r.depth} nodes ${r.nodes} in ${r.elapsedMs}ms best ${r.bestMove!.uci}');
    expect(r.depth, greaterThanOrEqualTo(3));
  });

  test('sees a knight fork two plies deep', () {
    // White Nc3 can go to d5?? no. Classic: Nf3-e5? Use Nd5 forking Kc7 and Qb6? Keep simple:
    // White: Ke1, Nd4; Black: Kb7, Qf7 (fork square: Nc6? no). Use Ne6 forking K on c7 and Q on g7? knight from d4 to e6 hits c7, g7.
    final r = analyze('8/2k3q1/8/8/3N4/8/8/4K3 w - - 0 1');
    expect(r.bestMove!.uci, 'd4e6');
  });
}
