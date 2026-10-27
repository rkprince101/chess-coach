import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import 'evaluator.dart';

/// Score assigned to a checkmate at the root; mates found deeper in the tree
/// are scored slightly lower so the engine prefers the shortest mate.
const int mateScore = 100000;
const int _maxPly = 64;
const int _infinity = 1 << 30;

bool isMateScore(int score) => score.abs() > mateScore - _maxPly;

/// Number of full moves until mate for a mate score (positive when the side
/// to move is mating, negative when being mated).
int mateIn(int score) {
  final plies = mateScore - score.abs();
  final moves = (plies + 1) ~/ 2;
  return score > 0 ? moves : -moves;
}

/// Human readable score, e.g. `+1.35` or `#3`, from White's point of view.
String formatScore(int scoreForSideToMove, Side sideToMove) {
  final white = sideToMove == Side.white ? scoreForSideToMove : -scoreForSideToMove;
  if (isMateScore(white)) {
    final m = mateIn(white);
    return m > 0 ? '#$m' : '#-${-m}';
  }
  final pawns = white / 100;
  return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
}

class RootMove {
  const RootMove({required this.move, required this.score});

  final Move move;

  /// Score from the point of view of the side to move.
  final int score;
}

class SearchResult {
  const SearchResult({
    required this.fen,
    required this.bestMove,
    required this.score,
    required this.depth,
    required this.pv,
    required this.nodes,
    required this.rootMoves,
    required this.elapsedMs,
  });

  final String fen;
  final Move? bestMove;

  /// Score from the point of view of the side to move.
  final int score;
  final int depth;
  final List<Move> pv;
  final int nodes;

  /// Every legal root move with a shallow full-window score, best first.
  final List<RootMove> rootMoves;
  final int elapsedMs;

  bool get isGameOver => bestMove == null;

  Map<String, dynamic> toJson() => {
        'fen': fen,
        'bestMove': bestMove?.uci,
        'score': score,
        'depth': depth,
        'pv': pv.map((m) => m.uci).toList(),
        'nodes': nodes,
        'rootMoves': rootMoves.map((r) => {'uci': r.move.uci, 'score': r.score}).toList(),
        'elapsedMs': elapsedMs,
      };

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        fen: json['fen'] as String,
        bestMove: json['bestMove'] == null ? null : Move.parse(json['bestMove'] as String),
        score: json['score'] as int,
        depth: json['depth'] as int,
        pv: (json['pv'] as List).map((u) => Move.parse(u as String)!).toList(),
        nodes: json['nodes'] as int,
        rootMoves: (json['rootMoves'] as List)
            .map((r) => RootMove(
                  move: Move.parse(r['uci'] as String)!,
                  score: r['score'] as int,
                ))
            .toList(),
        elapsedMs: json['elapsedMs'] as int,
      );
}

/// Entry point suitable for `compute`: takes and returns plain maps so the
/// payload crosses isolate boundaries on every platform.
Map<String, dynamic> runSearch(Map<String, dynamic> request) {
  final pos = Chess.fromSetup(Setup.parseFen(request['fen'] as String));
  final searcher = Searcher(
    timeLimitMs: request['timeMs'] as int,
    maxDepth: request['maxDepth'] as int,
  );
  return searcher.search(pos).toJson();
}

/// Iterative deepening alpha-beta search with quiescence, built on top of
/// dartchess move generation. Strong enough to spot hanging pieces, short
/// tactics and mates, which is what a coach needs to flag "wrong" moves.
class Searcher {
  Searcher({required this.timeLimitMs, required this.maxDepth});

  final int timeLimitMs;
  final int maxDepth;

  final Stopwatch _clock = Stopwatch();
  int _nodes = 0;
  bool _aborted = false;
  bool _allowAbort = false;
  final List<List<Move?>> _killers = List.generate(_maxPly, (_) => [null, null]);
  final List<List<Move>> _pv = List.generate(_maxPly, (_) => <Move>[]);

  SearchResult search(Position root) {
    _clock.start();
    final moves = _generateMoves(root);
    if (moves.isEmpty) {
      return SearchResult(
        fen: root.fen,
        bestMove: null,
        score: root.isCheck ? -mateScore : 0,
        depth: 0,
        pv: const [],
        nodes: 0,
        rootMoves: const [],
        elapsedMs: _clock.elapsedMilliseconds,
      );
    }

    // Shallow full-window pass: gives every root move an honest score, which
    // the opponent uses to pick "human" mistakes at lower skill levels.
    final shallow = <RootMove>[];
    for (final m in moves) {
      final child = root.playUnchecked(m);
      final s = -_negamax(child, 2, -_infinity, _infinity, 1);
      shallow.add(RootMove(move: m, score: s));
    }
    shallow.sort((a, b) => b.score.compareTo(a.score));

    final ordered = shallow.map((r) => r.move).toList();
    Move best = ordered.first;
    int bestScore = shallow.first.score;
    List<Move> bestPv = [best];
    var completedDepth = 0;

    _allowAbort = true;
    for (var depth = 1; depth <= maxDepth; depth++) {
      var alpha = -_infinity;
      const beta = _infinity;
      Move? iterBest;
      var iterScore = -_infinity;
      List<Move> iterPv = const [];
      final iterScores = <Move, int>{};

      for (final m in ordered) {
        final child = root.playUnchecked(m);
        final s = -_negamax(child, depth - 1, -beta, -alpha, 1);
        if (_aborted) break;
        iterScores[m] = s;
        if (s > iterScore) {
          iterScore = s;
          iterBest = m;
          iterPv = [m, ..._pv[1]];
        }
        if (s > alpha) alpha = s;
      }
      if (_aborted) break;

      best = iterBest!;
      bestScore = iterScore;
      bestPv = iterPv;
      completedDepth = depth;

      // Best move first, then the rest by this iteration's scores.
      ordered.sort((a, b) {
        if (a == best) return -1;
        if (b == best) return 1;
        return (iterScores[b] ?? -_infinity).compareTo(iterScores[a] ?? -_infinity);
      });

      if (isMateScore(bestScore)) break;
      if (_clock.elapsedMilliseconds > timeLimitMs * 0.5) break;
    }

    // Keep the deep best move at the top of the root move list.
    final rootMoves = [
      RootMove(move: best, score: bestScore),
      ...shallow.where((r) => r.move != best),
    ];

    return SearchResult(
      fen: root.fen,
      bestMove: best,
      score: bestScore,
      depth: completedDepth,
      pv: bestPv,
      nodes: _nodes,
      rootMoves: rootMoves,
      elapsedMs: _clock.elapsedMilliseconds,
    );
  }

  int _negamax(Position pos, int depth, int alpha, int beta, int ply) {
    _nodes++;
    if (_allowAbort && (_nodes & 2047) == 0 && _clock.elapsedMilliseconds > timeLimitMs) {
      _aborted = true;
    }
    if (_aborted) return 0;
    _pv[ply].clear();

    if (pos.isInsufficientMaterial) return 0;
    if (pos.halfmoves >= 100) return 0;

    final inCheck = pos.isCheck;
    if (inCheck && depth < 3) depth += 1;

    if (depth <= 0 || ply >= _maxPly - 1) return _quiescence(pos, alpha, beta, ply);

    final moves = _generateMoves(pos);
    if (moves.isEmpty) return inCheck ? -mateScore + ply : 0;
    _orderMoves(pos, moves, ply);

    var bestScore = -_infinity;
    for (final m in moves) {
      final child = pos.playUnchecked(m);
      final score = -_negamax(child, depth - 1, -beta, -alpha, ply + 1);
      if (_aborted) return 0;
      if (score > bestScore) {
        bestScore = score;
        if (score > alpha) {
          alpha = score;
          _pv[ply]
            ..clear()
            ..add(m)
            ..addAll(_pv[ply + 1]);
          if (score >= beta) {
            if (!_isCapture(pos, m)) {
              final k = _killers[ply];
              if (k[0] != m) {
                k[1] = k[0];
                k[0] = m;
              }
            }
            return score;
          }
        }
      }
    }
    return bestScore;
  }

  int _quiescence(Position pos, int alpha, int beta, int ply) {
    _nodes++;
    if (_allowAbort && (_nodes & 2047) == 0 && _clock.elapsedMilliseconds > timeLimitMs) {
      _aborted = true;
    }
    if (_aborted) return 0;

    final standPat = evaluate(pos);
    if (ply >= _maxPly - 1) return standPat;
    if (standPat >= beta) return standPat;
    if (standPat > alpha) alpha = standPat;

    final moves = _generateMoves(pos);
    if (moves.isEmpty) return pos.isCheck ? -mateScore + ply : 0;

    final captures = moves.where((m) => _isCapture(pos, m) || _isPromotion(m)).toList();
    _orderMoves(pos, captures, ply);

    var best = standPat;
    for (final m in captures) {
      // Delta pruning: skip captures that cannot possibly raise alpha.
      final gain = _capturedValue(pos, m) + (_isPromotion(m) ? queenValue : 0);
      if (standPat + gain + 200 < alpha) continue;
      final child = pos.playUnchecked(m);
      final score = -_quiescence(child, -beta, -alpha, ply + 1);
      if (_aborted) return 0;
      if (score > best) {
        best = score;
        if (score > alpha) {
          alpha = score;
          if (score >= beta) return score;
        }
      }
    }
    return best;
  }

  List<Move> _generateMoves(Position pos) {
    final moves = <Move>[];
    final backranks = SquareSet.backranks;
    for (final entry in pos.legalMoves.entries) {
      final from = entry.key;
      final isPawn = pos.board.roleAt(from) == Role.pawn;
      for (final to in entry.value.squares) {
        if (isPawn && backranks.has(to)) {
          moves.add(NormalMove(from: from, to: to, promotion: Role.queen));
          moves.add(NormalMove(from: from, to: to, promotion: Role.knight));
        } else {
          moves.add(NormalMove(from: from, to: to));
        }
      }
    }
    return moves;
  }

  bool _isCapture(Position pos, Move m) {
    if (m is! NormalMove) return false;
    final target = pos.board.sideAt(m.to);
    if (target != null) return target != pos.turn;
    return pos.board.roleAt(m.from) == Role.pawn && m.to == pos.epSquare;
  }

  bool _isPromotion(Move m) => m is NormalMove && m.promotion != null;

  int _capturedValue(Position pos, Move m) {
    if (m is! NormalMove) return 0;
    final role = pos.board.roleAt(m.to);
    if (role != null && pos.board.sideAt(m.to) != pos.turn) return pieceValue(role);
    if (pos.board.roleAt(m.from) == Role.pawn && m.to == pos.epSquare) return pawnValue;
    return 0;
  }

  void _orderMoves(Position pos, List<Move> moves, int ply) {
    final pvMove = ply < _pv.length && _pv[ply].isNotEmpty ? _pv[ply].first : null;
    final killers = _killers[ply];
    int scoreOf(Move m) {
      if (m == pvMove) return 1000000;
      var s = 0;
      final victim = _capturedValue(pos, m);
      if (victim > 0) {
        final attacker = pieceValue(pos.board.roleAt((m as NormalMove).from)!);
        s += 10000 + victim * 10 - attacker ~/ 10;
      }
      if (_isPromotion(m)) s += 9000;
      if (m == killers[0]) s += 5000;
      if (m == killers[1]) s += 4000;
      return s;
    }

    final scored = [for (final m in moves) (m, scoreOf(m))];
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    for (var i = 0; i < moves.length; i++) {
      moves[i] = scored[i].$1;
    }
  }
}

/// Picks the move an opponent of the given skill level (1-8) would play from
/// a finished search. Level 8 always plays the best move; lower levels
/// sometimes prefer a plausible but weaker alternative.
Move pickMoveForLevel(SearchResult result, int level, math.Random random) {
  final best = result.bestMove!;
  if (level >= 8 || result.rootMoves.length < 2) return best;

  const bestProbability = [0.10, 0.20, 0.35, 0.50, 0.65, 0.80, 0.90, 1.0];
  const thresholdCp = [350, 250, 170, 110, 70, 40, 20, 0];
  final idx = (level - 1).clamp(0, 7);
  if (random.nextDouble() < bestProbability[idx]) return best;

  final top = result.rootMoves.first.score;
  final candidates = result.rootMoves
      .where((r) => r.move == best || (top - r.score <= thresholdCp[idx] && !isMateScore(r.score)))
      .toList();
  if (candidates.isEmpty) return best;
  return candidates[random.nextInt(candidates.length)].move;
}
