import 'dart:async';

import 'package:chessground/chessground.dart' show Arrow, Shape;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../analysis/game_analysis.dart';
import '../engine/engine_service.dart';
import '../models/move_quality.dart';
import '../services/match_history.dart';

/// Steps through a recorded game and runs the full-game engine analysis on
/// demand. The analysis is written back to the match history so it only
/// ever has to run once per game.
class AnalysisController extends ChangeNotifier {
  AnalysisController({required MatchRecord record, required this.engine, this.history})
      : _record = record {
    var pos = record.startPosition;
    positions.add(pos);
    for (final m in record.parsedMoves) {
      final (after, san) = pos.makeSan(m);
      moves.add(m);
      sans.add(san);
      positions.add(after);
      pos = after;
    }
    ply = moves.length;
  }

  final EngineService engine;
  final MatchHistory? history;
  MatchRecord _record;

  /// Positions of the game: the start, then one after each move.
  final List<Position> positions = [];
  final List<Move> moves = [];
  final List<String> sans = [];

  /// How many moves are applied on the board (0 = start position).
  int ply = 0;

  bool running = false;
  int progressDone = 0;
  int progressTotal = 0;
  String? error;
  bool _disposed = false;
  int _run = 0;

  MatchRecord get record => _record;

  /// Analysis that matches this game's moves, if any.
  GameAnalysis? get analysis {
    final a = _record.analysis;
    return a != null && a.plies.length == moves.length ? a : null;
  }

  Position get position => positions[ply];
  Move? get lastMove => ply == 0 ? null : moves[ply - 1];
  bool get atStart => ply == 0;
  bool get atEnd => ply >= moves.length;

  /// Grade of the move that led to the shown position: from the analysis,
  /// else from the live coach (player's moves only).
  MoveQuality? qualityOf(int moveIndex) =>
      analysis?.plies[moveIndex].quality ?? _record.liveGrades[moveIndex];

  PlyAnalysis? get currentPly => ply == 0 ? null : analysis?.plies[ply - 1];

  int? get evalCpWhite => analysis?.evalCp[ply];
  String? get evalText => analysis?.evalText[ply];

  /// The played move in its grade's colour, and the engine's choice in green
  /// when it differs.
  Set<Shape> get shapes {
    final current = currentPly;
    final played = lastMove;
    if (current == null || played is! NormalMove) return const {};
    final shapes = <Shape>{
      Arrow(color: current.quality.color.withValues(alpha: 0.8), orig: played.from, dest: played.to),
    };
    final best = current.bestMove;
    if (best is NormalMove && best.uci != played.uci && current.quality.isBad) {
      shapes.add(Arrow(color: const Color(0xCC2E7D32), orig: best.from, dest: best.to));
    }
    return shapes;
  }

  void goTo(int index) {
    final clamped = index.clamp(0, moves.length);
    if (clamped == ply) return;
    ply = clamped;
    notifyListeners();
  }

  void next() => goTo(ply + 1);
  void previous() => goTo(ply - 1);
  void first() => goTo(0);
  void last() => goTo(moves.length);

  /// Jumps to the next move graded inaccuracy or worse, wrapping around.
  void nextMistake() {
    final a = analysis;
    if (a == null) return;
    for (var step = 1; step <= moves.length; step++) {
      final i = (ply - 1 + step) % moves.length;
      if (a.plies[i].quality.isBad) {
        goTo(i + 1);
        return;
      }
    }
  }

  Future<void> analyse({required int timeMs}) async {
    if (running || moves.isEmpty) return;
    final run = ++_run;
    running = true;
    error = null;
    progressDone = 0;
    progressTotal = positions.length;
    notifyListeners();
    try {
      final result = await analyzeGame(
        engine: engine,
        start: positions.first,
        moves: moves,
        timeMs: timeMs,
        isCancelled: () => _disposed || run != _run,
        onProgress: (done, total) {
          if (_disposed || run != _run) return;
          progressDone = done;
          progressTotal = total;
          notifyListeners();
        },
      );
      if (result == null || _disposed || run != _run) return;
      _record = _record.copyWith(analysis: result);
      final store = history;
      if (store != null && store.byId(_record.id) != null) unawaited(store.upsert(_record));
    } catch (e) {
      if (!_disposed) error = 'Analysis failed: $e';
    } finally {
      if (!_disposed && run == _run) {
        running = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    if (!running) return;
    _run++;
    running = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
