import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../coach/facts.dart' show hangingPieces, lineToSan;
import '../coach/opening_book.dart' as book;
import '../engine/engine_service.dart';
import '../engine/evaluator.dart' show pieceValue;
import '../engine/search.dart';
import '../models/move_quality.dart';

/// Engine verdict on one move of an analysed game.
class PlyAnalysis {
  const PlyAnalysis({
    required this.quality,
    required this.winPercentLoss,
    required this.bestUci,
    required this.bestSan,
    required this.bestLine,
  });

  final MoveQuality quality;

  /// Expected-win percentage the mover gave away versus the engine's choice.
  final double winPercentLoss;

  /// The engine's preferred move in the position before this move.
  final String? bestUci;
  final String? bestSan;

  /// The engine's main line from the position before this move, in SAN.
  final String bestLine;

  Move? get bestMove => bestUci == null ? null : Move.parse(bestUci!);

  Map<String, Object?> toJson() => {
        'q': quality.name,
        'loss': double.parse(winPercentLoss.toStringAsFixed(2)),
        'best': bestUci,
        'bestSan': bestSan,
        'line': bestLine,
      };

  static PlyAnalysis? fromJson(Object? json) {
    if (json is! Map) return null;
    final quality = MoveQuality.values.asNameMap()[json['q']];
    final loss = json['loss'];
    if (quality == null || loss is! num) return null;
    return PlyAnalysis(
      quality: quality,
      winPercentLoss: loss.toDouble(),
      bestUci: json['best'] as String?,
      bestSan: json['bestSan'] as String?,
      bestLine: json['line'] as String? ?? '',
    );
  }
}

/// Full-game engine analysis: an evaluation for every position and a grade
/// for every move, for both players.
class GameAnalysis {
  const GameAnalysis({
    required this.timeMs,
    required this.analysedAt,
    required this.firstMover,
    required this.evalCp,
    required this.evalText,
    required this.plies,
  });

  /// Engine time spent per position.
  final int timeMs;
  final DateTime analysedAt;

  /// Side that made the first move ([plies] alternate from there).
  final Side firstMover;

  /// Evaluation of each position (one more than [plies]) in centipawns from
  /// White's point of view, mates folded into ±3000.
  final List<int> evalCp;

  /// The same evaluations as display text, e.g. "+0.35", "#3" or "1-0".
  final List<String> evalText;
  final List<PlyAnalysis> plies;

  Side moverOf(int ply) => ply.isEven ? firstMover : firstMover.opposite;

  Iterable<PlyAnalysis> movesOf(Side side) sync* {
    for (var i = 0; i < plies.length; i++) {
      if (moverOf(i) == side) yield plies[i];
    }
  }

  /// Lichess-style accuracy for [side], or null if it made no moves.
  double? accuracy(Side side) {
    final losses = movesOf(side).map((p) => p.winPercentLoss).toList();
    return losses.isEmpty ? null : accuracyFromLosses(losses);
  }

  Map<MoveQuality, int> counts(Side side) {
    final counts = <MoveQuality, int>{};
    for (final p in movesOf(side)) {
      counts.update(p.quality, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Map<String, Object?> toJson() => {
        'timeMs': timeMs,
        'at': analysedAt.toIso8601String(),
        'first': firstMover.name,
        'evalCp': evalCp,
        'evalText': evalText,
        'plies': [for (final p in plies) p.toJson()],
      };

  static GameAnalysis? fromJson(Object? json) {
    if (json is! Map) return null;
    final first = Side.values.asNameMap()[json['first']];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    final evalCp = json['evalCp'];
    final evalText = json['evalText'];
    final plies = json['plies'];
    if (first == null || at == null || evalCp is! List || evalText is! List || plies is! List) return null;
    final parsed = plies.map(PlyAnalysis.fromJson).toList();
    if (parsed.contains(null) || evalCp.length != plies.length + 1 || evalText.length != evalCp.length) {
      return null;
    }
    return GameAnalysis(
      timeMs: json['timeMs'] as int? ?? 0,
      analysedAt: at,
      firstMover: first,
      evalCp: evalCp.cast<int>(),
      evalText: evalText.cast<String>(),
      plies: parsed.cast<PlyAnalysis>(),
    );
  }
}

/// Runs the engine over every position of a game and grades each move.
/// Returns null when [isCancelled] turns true before it finishes.
Future<GameAnalysis?> analyzeGame({
  required EngineService engine,
  required Position start,
  required List<Move> moves,
  required int timeMs,
  bool Function()? isCancelled,
  void Function(int done, int total)? onProgress,
}) async {
  final positions = [start];
  for (final m in moves) {
    positions.add(positions.last.play(m));
  }
  final results = <SearchResult?>[];
  for (final (i, pos) in positions.indexed) {
    if (isCancelled?.call() ?? false) return null;
    onProgress?.call(i, positions.length);
    results.add(pos.isGameOver ? null : await engine.analyze(pos.fen, timeMs: timeMs, maxDepth: 10));
  }
  if (isCancelled?.call() ?? false) return null;
  onProgress?.call(positions.length, positions.length);
  return gradeGame(positions: positions, moves: moves, results: results, timeMs: timeMs);
}

/// Grades a game from per-position engine results. [results] has one entry
/// per position in [positions], null for positions where the game is over.
GameAnalysis gradeGame({
  required List<Position> positions,
  required List<Move> moves,
  required List<SearchResult?> results,
  required int timeMs,
  DateTime? now,
}) {
  final evalCp = <int>[];
  final evalText = <String>[];
  for (final (i, pos) in positions.indexed) {
    final (cp, text) = _evalOf(pos, results[i]);
    evalCp.add(cp);
    evalText.add(text);
  }

  final sans = <String>[];
  final plies = <PlyAnalysis>[];
  for (var i = 0; i < moves.length; i++) {
    final before = positions[i];
    final after = positions[i + 1];
    final move = moves[i];
    sans.add(before.makeSan(move).$2);
    final analysis = results[i]!;

    final bestScore = analysis.score;
    final int playedScore;
    if (after.isCheckmate) {
      playedScore = mateScore - 1;
    } else if (after.isGameOver) {
      playedScore = 0;
    } else {
      playedScore = -results[i + 1]!.score;
    }
    final bestMove = analysis.bestMove;
    final playedIsBest = bestMove != null && bestMove.uci == move.uci;
    final bestWin = winPercent(scoreToCp(bestScore));
    final playedWin = winPercent(scoreToCp(playedScore));
    // The deeper search after the move can rate it above the engine's own
    // pick; that is no loss.
    final loss = math.max(0.0, bestWin - playedWin);

    var quality = classifyMove(bestScore: bestScore, playedScore: playedScore, playedIsBest: playedIsBest);
    if (quality == MoveQuality.best && !playedIsBest) quality = MoveQuality.excellent;

    if (before.legalMoves.values.fold(0, (n, dests) => n + dests.size) == 1) {
      quality = MoveQuality.forced;
    } else if (!quality.isBad && book.isBookLine(sans)) {
      quality = MoveQuality.book;
    } else if (quality == MoveQuality.best || quality == MoveQuality.excellent) {
      if (_isSacrifice(before, after, move) && playedWin >= 50 && bestWin < 95) {
        quality = MoveQuality.brilliant;
      } else if (playedIsBest && _isOnlyMove(analysis, bestWin)) {
        quality = MoveQuality.great;
      }
    } else if ((quality == MoveQuality.mistake || quality == MoveQuality.blunder) &&
        plies.isNotEmpty &&
        plies.last.quality.isBad &&
        bestWin >= 65 &&
        playedWin >= 35) {
      // The opponent just erred and this move let the chance slip without
      // losing the game outright.
      quality = MoveQuality.miss;
    }

    plies.add(PlyAnalysis(
      quality: quality,
      winPercentLoss: loss,
      bestUci: bestMove?.uci,
      bestSan: bestMove == null ? null : before.makeSan(bestMove).$2,
      bestLine: lineToSan(before, analysis.pv),
    ));
  }

  return GameAnalysis(
    timeMs: timeMs,
    analysedAt: now ?? DateTime.now(),
    firstMover: positions.first.turn,
    evalCp: evalCp,
    evalText: evalText,
    plies: plies,
  );
}

(int, String) _evalOf(Position pos, SearchResult? result) {
  if (pos.isCheckmate) {
    // The side to move is mated.
    return pos.turn == Side.white ? (-3000, '0-1') : (3000, '1-0');
  }
  if (result == null) return (0, '½-½');
  final cp = scoreToCp(result.score);
  return (pos.turn == Side.white ? cp : -cp, formatScore(result.score, pos.turn));
}

/// The move puts a piece worth at least a minor piece en prise (the moved
/// piece, or one it stops guarding) for clearly less than it is worth. The
/// caller checks the engine still likes it, which makes it a sacrifice.
bool _isSacrifice(Position before, Position after, Move move) {
  if (after.isCheckmate || move is! NormalMove) return false;
  final captured = before.board.pieceAt(move.to);
  final gained = captured == null ? 0 : pieceValue(captured.role);
  final mover = before.turn;
  final alreadyHanging = {for (final h in hangingPieces(before, mover)) h.square};
  return hangingPieces(after, mover).any((h) =>
      (h.square == move.to || !alreadyHanging.contains(h.square)) &&
      pieceValue(h.piece.role) >= 300 &&
      pieceValue(h.piece.role) > gained + 100);
}

/// Every alternative is clearly worse than the engine's move.
bool _isOnlyMove(SearchResult analysis, double bestWin) {
  if (analysis.rootMoves.length < 2) return false;
  final secondWin = winPercent(scoreToCp(analysis.rootMoves[1].score));
  return bestWin - secondWin >= 20 && bestWin >= 30 && bestWin <= 97;
}
