import 'package:dartchess/dartchess.dart';

import '../engine/evaluator.dart';

/// Board facts computed locally with dartchess. They ground the AI coach's
/// explanations in verified information (what hangs, what the engine line
/// wins) instead of leaving it to imagine the position.

String roleName(Role role) => switch (role) {
      Role.pawn => 'pawn',
      Role.knight => 'knight',
      Role.bishop => 'bishop',
      Role.rook => 'rook',
      Role.queen => 'queen',
      Role.king => 'king',
    };

String sideName(Side side) => side == Side.white ? 'White' : 'Black';

class HangingPiece {
  const HangingPiece({
    required this.square,
    required this.piece,
    required this.attackers,
    required this.defenders,
    required this.cheapestAttacker,
  });

  final Square square;
  final Piece piece;
  final int attackers;
  final int defenders;
  final Role cheapestAttacker;

  bool get undefended => defenders == 0;

  String describe() {
    final what = '${sideName(piece.color)} ${roleName(piece.role)} on ${square.name}';
    if (undefended) return '$what is attacked by a ${roleName(cheapestAttacker)} and undefended';
    return '$what is attacked by a ${roleName(cheapestAttacker)}, which is worth less';
  }
}

/// Pieces of [side] that can be captured profitably right now.
List<HangingPiece> hangingPieces(Position pos, Side side) {
  final board = pos.board;
  final result = <HangingPiece>[];
  for (final (sq, piece) in board.pieces) {
    if (piece.color != side || piece.role == Role.king) continue;
    final attackers = board.attacksTo(sq, side.opposite);
    if (attackers.isEmpty) continue;
    final defenders = board.attacksTo(sq, side);
    var cheapest = Role.king;
    var cheapestValue = kingValue;
    for (final a in attackers.squares) {
      final role = board.roleAt(a)!;
      final v = pieceValue(role);
      if (v < cheapestValue) {
        cheapestValue = v;
        cheapest = role;
      }
    }
    if (defenders.isEmpty || cheapestValue < pieceValue(piece.role)) {
      result.add(HangingPiece(
        square: sq,
        piece: piece,
        attackers: attackers.size,
        defenders: defenders.size,
        cheapestAttacker: cheapest,
      ));
    }
  }
  result.sort((a, b) => pieceValue(b.piece.role).compareTo(pieceValue(a.piece.role)));
  return result;
}

/// Describes a move in words: "Nxe5 (knight captures pawn on e5, check)".
String describeMove(Position before, Move move) {
  final san = before.makeSan(move).$2;
  final parts = <String>[];
  if (move is NormalMove) {
    final piece = before.board.pieceAt(move.from);
    final target = before.board.pieceAt(move.to);
    if (piece?.role == Role.king && (move.to.file - move.from.file).abs() >= 2 ||
        (piece?.role == Role.king && target?.color == piece?.color)) {
      parts.add(move.to.file > move.from.file ? 'castles kingside' : 'castles queenside');
    } else if (piece != null) {
      if (target != null && target.color != piece.color) {
        parts.add('${roleName(piece.role)} captures ${roleName(target.role)} on ${move.to.name}');
      } else if (piece.role == Role.pawn && move.to == before.epSquare) {
        parts.add('pawn captures en passant on ${move.to.name}');
      } else {
        parts.add('${roleName(piece.role)} from ${move.from.name} to ${move.to.name}');
      }
      if (move.promotion != null) parts.add('promotes to ${roleName(move.promotion!)}');
    }
  }
  final after = before.playUnchecked(move);
  if (after.isCheckmate) {
    parts.add('checkmate');
  } else if (after.isCheck) {
    parts.add('check');
  }
  return '$san (${parts.join(', ')})';
}

/// Renders a principal variation as numbered SAN, e.g. "12...Nf6 13.Bxf7+ Kxf7".
String lineToSan(Position pos, List<Move> line, {int maxPlies = 8}) {
  final buffer = StringBuffer();
  var p = pos;
  var count = 0;
  for (final m in line) {
    if (count >= maxPlies) break;
    if (!p.isLegal(m)) break;
    if (p.turn == Side.white) {
      buffer.write('${p.fullmoves}.');
    } else if (count == 0) {
      buffer.write('${p.fullmoves}...');
    }
    buffer.write('${p.makeSan(m).$2} ');
    p = p.playUnchecked(m);
    count++;
  }
  return buffer.toString().trim();
}

/// Material balance in pawns from White's point of view, e.g. "+3.0 (White is up a knight)".
String describeMaterial(Position pos) {
  final cp = materialBalance(pos.board);
  if (cp == 0) return 'material is equal';
  final side = cp > 0 ? 'White' : 'Black';
  return '$side is up ${(cp.abs() / 100).toStringAsFixed(1)} pawns of material';
}

/// Signals that lead into rule lessons: castling, en passant and promotion.
class SpecialMoveAvailability {
  const SpecialMoveAvailability({
    required this.canCastle,
    required this.canEnPassant,
    required this.canPromote,
  });

  final bool canCastle;
  final bool canEnPassant;
  final bool canPromote;
}

SpecialMoveAvailability specialMoves(Position pos) {
  final legal = pos.legalMoves;
  final king = pos.board.kingOf(pos.turn);
  var canCastle = false;
  if (king != null) {
    final dests = legal[king] ?? SquareSet.empty;
    for (final d in dests.squares) {
      if (pos.board.sideAt(d) == pos.turn || (d.file - king.file).abs() >= 2) canCastle = true;
    }
  }
  var canEnPassant = false;
  final ep = pos.epSquare;
  if (ep != null) {
    for (final entry in legal.entries) {
      if (pos.board.roleAt(entry.key) == Role.pawn && entry.value.has(ep)) canEnPassant = true;
    }
  }
  var canPromote = false;
  for (final entry in legal.entries) {
    if (pos.board.roleAt(entry.key) == Role.pawn &&
        entry.value.isIntersected(SquareSet.backranks)) {
      canPromote = true;
    }
  }
  return SpecialMoveAvailability(
    canCastle: canCastle,
    canEnPassant: canEnPassant,
    canPromote: canPromote,
  );
}

/// Opening-principle observations about the game so far (first 12 moves).
List<String> openingObservations(List<(Position, Move)> history, Side player) {
  final notes = <String>[];
  final playerMoves = <(Position, Move)>[];
  for (final entry in history) {
    if (entry.$1.turn == player) playerMoves.add(entry);
  }
  if (playerMoves.isEmpty || playerMoves.length > 12) return notes;

  final movedPieces = <Square, int>{};
  var castled = false;
  var queenMoves = 0;
  var pawnMoves = 0;
  var minorDeveloped = 0;
  var edgePawnMoves = 0;
  for (final (pos, move) in playerMoves) {
    if (move is! NormalMove) continue;
    final piece = pos.board.pieceAt(move.from);
    if (piece == null) continue;
    final target = pos.board.pieceAt(move.to);
    final isCastle = piece.role == Role.king &&
        ((move.to.file - move.from.file).abs() >= 2 || target?.color == piece.color);
    if (isCastle) castled = true;
    if (piece.role == Role.queen) queenMoves++;
    if (piece.role == Role.pawn) {
      pawnMoves++;
      if (move.from.file == 0 || move.from.file == 7) edgePawnMoves++;
    }
    if ((piece.role == Role.knight || piece.role == Role.bishop) &&
        SquareSet.backranks.has(move.from)) {
      minorDeveloped++;
    }
    movedPieces.update(move.to, (v) => v + 1, ifAbsent: () => 1);
  }

  final n = playerMoves.length;
  if (n >= 4 && minorDeveloped == 0) {
    notes.add('You have not developed a knight or bishop yet after $n moves.');
  }
  if (n >= 4 && queenMoves >= 2) {
    notes.add('Your queen has moved $queenMoves times already; early queen sorties can be chased with tempo.');
  }
  if (n >= 6 && pawnMoves > n / 2) {
    notes.add('More than half of your moves were pawn moves; pieces win games in the opening.');
  }
  if (edgePawnMoves >= 2 && n <= 8) {
    notes.add('Edge pawn moves (a/h files) rarely help development.');
  }
  if (n >= 8 && !castled) {
    notes.add('Your king is still in the centre after $n moves; castling is overdue.');
  }
  return notes;
}

/// "your", "the opponent's", or "White's" depending on who is watching.
String ownerWord(Side pieceSide, Side? viewer) {
  if (viewer == null) return pieceSide == Side.white ? "White's" : "Black's";
  return pieceSide == viewer ? 'your' : "the opponent's";
}

bool isCastlingMove(Position before, Move move) {
  if (move is! NormalMove) return false;
  final piece = before.board.pieceAt(move.from);
  if (piece?.role != Role.king) return false;
  final target = before.board.pieceAt(move.to);
  return (move.to.file - move.from.file).abs() >= 2 || target?.color == piece!.color;
}

/// Plain-English description of a move for players who do not read
/// notation yet, e.g. "your knight jumps from f3 to e5 and captures a pawn,
/// giving check". [viewer] makes the wording relative ("your"/"the opponent's").
String friendlyMove(Position before, Move move, {Side? viewer}) {
  if (move is! NormalMove) return before.makeSan(move).$2;
  final piece = before.board.pieceAt(move.from);
  if (piece == null) return before.makeSan(move).$2;
  final owner = ownerWord(piece.color, viewer);
  final buffer = StringBuffer();

  if (isCastlingMove(before, move)) {
    final kingside = move.to.file > move.from.file;
    buffer.write('$owner king castles ${kingside ? 'kingside' : 'queenside'} '
        '(king to ${kingCastlesTo(piece.color, kingside ? CastlingSide.king : CastlingSide.queen).name}, '
        'rook to ${rookCastlesTo(piece.color, kingside ? CastlingSide.king : CastlingSide.queen).name})');
  } else {
    final target = before.board.pieceAt(move.to);
    final verb = switch (piece.role) {
      Role.knight => 'jumps',
      Role.pawn => 'steps',
      _ => 'moves',
    };
    buffer.write('$owner ${roleName(piece.role)} $verb from ${move.from.name} to ${move.to.name}');
    if (target != null && target.color != piece.color) {
      buffer.write(' and captures ${ownerWord(target.color, viewer)} ${roleName(target.role)}');
    } else if (piece.role == Role.pawn && move.to == before.epSquare) {
      buffer.write(' and captures a pawn en passant');
    }
    if (move.promotion != null) buffer.write(', promoting to a ${roleName(move.promotion!)}');
  }

  final after = before.playUnchecked(move);
  if (after.isCheckmate) {
    buffer.write(': checkmate');
  } else if (after.isCheck) {
    buffer.write(', giving check');
  }
  final text = buffer.toString();
  return text[0].toUpperCase() + text.substring(1);
}

/// A whole line in plain English, one numbered sentence per move.
String friendlyLine(Position start, List<Move> line, {Side? viewer, int maxPlies = 6}) {
  final parts = <String>[];
  var p = start;
  for (final m in line) {
    if (parts.length >= maxPlies || !p.isLegal(m)) break;
    parts.add('${parts.length + 1}) ${friendlyMove(p, m, viewer: viewer)}.');
    p = p.playUnchecked(m);
  }
  return parts.join(' ');
}
