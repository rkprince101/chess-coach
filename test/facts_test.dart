import 'package:chess/coach/facts.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

Position fen(String f) => Chess.fromSetup(Setup.parseFen(f));

void main() {
  test('friendlyMove describes captures, checks and castling in words', () {
    final italian = fen('r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3');
    expect(
      friendlyMove(italian, NormalMove(from: Square.f3, to: Square.e5), viewer: Side.white),
      "Your knight jumps from f3 to e5 and captures the opponent's pawn",
    );
    expect(
      friendlyMove(italian, NormalMove(from: Square.f3, to: Square.e5), viewer: Side.black),
      "The opponent's knight jumps from f3 to e5 and captures your pawn",
    );

    final castle = fen('r3k2r/pppq1ppp/2npbn2/4p3/2B1P3/2NP1N2/PPPBQPPP/R3K2R w KQkq - 0 1');
    expect(
      friendlyMove(castle, NormalMove(from: Square.e1, to: Square.h1), viewer: Side.white),
      'Your king castles kingside (king to g1, rook to f1)',
    );

    final mate = fen('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1');
    expect(
      friendlyMove(mate, NormalMove(from: Square.a1, to: Square.a8)),
      "White's rook moves from a1 to a8: checkmate",
    );

    final check = fen('8/2k3q1/8/8/3N4/8/8/4K3 w - - 0 1');
    expect(
      friendlyMove(check, NormalMove(from: Square.d4, to: Square.e6), viewer: Side.white),
      'Your knight jumps from d4 to e6, giving check',
    );
  });

  test('friendlyLine numbers each move and stops at illegal tails', () {
    final start = fen('3qr1k1/5ppp/8/8/8/8/4QPPP/4R1K1 w - - 0 1');
    final line = [
      NormalMove(from: Square.e2, to: Square.e8),
      NormalMove(from: Square.d8, to: Square.e8),
      NormalMove(from: Square.e1, to: Square.e8),
      NormalMove(from: Square.a1, to: Square.a2), // nonsense tail
    ];
    final text = friendlyLine(start, line, viewer: Side.white);
    expect(text, startsWith("1) Your queen moves from e2 to e8 and captures the opponent's rook, giving check."));
    expect(text, contains('3) Your rook moves from e1 to e8'));
    expect(text, endsWith('checkmate.'));
    expect(text, isNot(contains('4)')));
  });

  test('hangingPieces spots an undefended attacked piece', () {
    final pos = fen('4k3/8/8/3q4/8/2N5/8/4K3 w - - 0 1');
    final hanging = hangingPieces(pos, Side.black);
    expect(hanging, hasLength(1));
    expect(hanging.first.describe(), 'Black queen on d5 is attacked by a knight and undefended');
  });
}
