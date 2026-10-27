import 'package:dartchess/dartchess.dart';

/// Centipawn piece values.
const int pawnValue = 100;
const int knightValue = 320;
const int bishopValue = 330;
const int rookValue = 500;
const int queenValue = 900;
const int kingValue = 20000;

int pieceValue(Role role) => switch (role) {
      Role.pawn => pawnValue,
      Role.knight => knightValue,
      Role.bishop => bishopValue,
      Role.rook => rookValue,
      Role.queen => queenValue,
      Role.king => kingValue,
    };

// Piece-square tables (Simplified Evaluation Function, Tomasz Michniewski).
// Written from White's point of view with rank 8 on the first row, so the
// table index for a LERF square is `(7 - rank) * 8 + file` for White and
// `rank * 8 + file` for Black.
const List<int> _pawnTable = [
  0, 0, 0, 0, 0, 0, 0, 0, //
  50, 50, 50, 50, 50, 50, 50, 50,
  10, 10, 20, 30, 30, 20, 10, 10,
  5, 5, 10, 25, 25, 10, 5, 5,
  0, 0, 0, 20, 20, 0, 0, 0,
  5, -5, -10, 0, 0, -10, -5, 5,
  5, 10, 10, -20, -20, 10, 10, 5,
  0, 0, 0, 0, 0, 0, 0, 0,
];

const List<int> _knightTable = [
  -50, -40, -30, -30, -30, -30, -40, -50, //
  -40, -20, 0, 0, 0, 0, -20, -40,
  -30, 0, 10, 15, 15, 10, 0, -30,
  -30, 5, 15, 20, 20, 15, 5, -30,
  -30, 0, 15, 20, 20, 15, 0, -30,
  -30, 5, 10, 15, 15, 10, 5, -30,
  -40, -20, 0, 5, 5, 0, -20, -40,
  -50, -40, -30, -30, -30, -30, -40, -50,
];

const List<int> _bishopTable = [
  -20, -10, -10, -10, -10, -10, -10, -20, //
  -10, 0, 0, 0, 0, 0, 0, -10,
  -10, 0, 5, 10, 10, 5, 0, -10,
  -10, 5, 5, 10, 10, 5, 5, -10,
  -10, 0, 10, 10, 10, 10, 0, -10,
  -10, 10, 10, 10, 10, 10, 10, -10,
  -10, 5, 0, 0, 0, 0, 5, -10,
  -20, -10, -10, -10, -10, -10, -10, -20,
];

const List<int> _rookTable = [
  0, 0, 0, 0, 0, 0, 0, 0, //
  5, 10, 10, 10, 10, 10, 10, 5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  0, 0, 0, 5, 5, 0, 0, 0,
];

const List<int> _queenTable = [
  -20, -10, -10, -5, -5, -10, -10, -20, //
  -10, 0, 0, 0, 0, 0, 0, -10,
  -10, 0, 5, 5, 5, 5, 0, -10,
  -5, 0, 5, 5, 5, 5, 0, -5,
  0, 0, 5, 5, 5, 5, 0, -5,
  -10, 5, 5, 5, 5, 5, 0, -10,
  -10, 0, 5, 0, 0, 0, 0, -10,
  -20, -10, -10, -5, -5, -10, -10, -20,
];

const List<int> _kingMiddleTable = [
  -30, -40, -40, -50, -50, -40, -40, -30, //
  -30, -40, -40, -50, -50, -40, -40, -30,
  -30, -40, -40, -50, -50, -40, -40, -30,
  -30, -40, -40, -50, -50, -40, -40, -30,
  -20, -30, -30, -40, -40, -30, -30, -20,
  -10, -20, -20, -20, -20, -20, -20, -10,
  20, 20, 0, 0, 0, 0, 20, 20,
  20, 30, 10, 0, 0, 10, 30, 20,
];

const List<int> _kingEndTable = [
  -50, -40, -30, -20, -20, -30, -40, -50, //
  -30, -20, -10, 0, 0, -10, -20, -30,
  -30, -10, 20, 30, 30, 20, -10, -30,
  -30, -10, 30, 40, 40, 30, -10, -30,
  -30, -10, 30, 40, 40, 30, -10, -30,
  -30, -10, 20, 30, 30, 20, -10, -30,
  -30, -30, 0, 0, 0, 0, -30, -30,
  -50, -30, -30, -30, -30, -30, -30, -50,
];

int _tableIndex(Square sq, Side side) =>
    side == Side.white ? (7 - sq.rank) * 8 + sq.file : sq.rank * 8 + sq.file;

/// Non-pawn material of one side, used to detect the endgame.
int nonPawnMaterial(Board board, Side side) {
  return board.piecesOf(side, Role.knight).size * knightValue +
      board.piecesOf(side, Role.bishop).size * bishopValue +
      board.piecesOf(side, Role.rook).size * rookValue +
      board.piecesOf(side, Role.queen).size * queenValue;
}

/// Material balance in centipawns from White's point of view.
int materialBalance(Board board) {
  var score = 0;
  for (final role in Role.values) {
    if (role == Role.king) continue;
    final v = pieceValue(role);
    score += (board.piecesOf(Side.white, role).size -
            board.piecesOf(Side.black, role).size) *
        v;
  }
  return score;
}

/// Static evaluation from the point of view of the side to move.
int evaluate(Position pos) {
  final board = pos.board;
  final endgame = nonPawnMaterial(board, Side.white) <= 1300 &&
      nonPawnMaterial(board, Side.black) <= 1300;

  var score = 0;
  for (final (sq, piece) in board.pieces) {
    final sign = piece.color == Side.white ? 1 : -1;
    final idx = _tableIndex(sq, piece.color);
    final pst = switch (piece.role) {
      Role.pawn => _pawnTable[idx],
      Role.knight => _knightTable[idx],
      Role.bishop => _bishopTable[idx],
      Role.rook => _rookTable[idx],
      Role.queen => _queenTable[idx],
      Role.king => endgame ? _kingEndTable[idx] : _kingMiddleTable[idx],
    };
    final value = piece.role == Role.king ? 0 : pieceValue(piece.role);
    score += sign * (value + pst);
  }

  score += _pawnStructure(board, Side.white) - _pawnStructure(board, Side.black);
  score += _rookFiles(board, Side.white) - _rookFiles(board, Side.black);
  if (board.piecesOf(Side.white, Role.bishop).size >= 2) score += 30;
  if (board.piecesOf(Side.black, Role.bishop).size >= 2) score -= 30;

  return pos.turn == Side.white ? score : -score;
}

int _pawnStructure(Board board, Side side) {
  final pawns = board.piecesOf(side, Role.pawn);
  var penalty = 0;
  for (var f = 0; f < 8; f++) {
    final fileMask = SquareSet.fromFile(File(f));
    final onFile = (pawns & fileMask).size;
    if (onFile == 0) continue;
    if (onFile > 1) penalty += 12 * (onFile - 1);
    final left = f > 0 ? SquareSet.fromFile(File(f - 1)) : SquareSet.empty;
    final right = f < 7 ? SquareSet.fromFile(File(f + 1)) : SquareSet.empty;
    if ((pawns & (left | right)).isEmpty) penalty += 10;
  }
  return -penalty;
}

int _rookFiles(Board board, Side side) {
  var bonus = 0;
  final ownPawns = board.piecesOf(side, Role.pawn);
  final enemyPawns = board.piecesOf(side.opposite, Role.pawn);
  for (final rook in board.piecesOf(side, Role.rook).squares) {
    final fileMask = SquareSet.fromFile(rook.file);
    if ((ownPawns & fileMask).isEmpty) {
      bonus += (enemyPawns & fileMask).isEmpty ? 20 : 10;
    }
  }
  return bonus;
}
