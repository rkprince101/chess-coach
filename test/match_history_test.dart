import 'dart:convert';

import 'package:chess/analysis/game_analysis.dart';
import 'package:chess/coach/coach_service.dart';
import 'package:chess/engine/engine_service.dart';
import 'package:chess/engine/search.dart';
import 'package:chess/models/move_quality.dart';
import 'package:chess/services/match_history.dart';
import 'package:chess/services/saved_game.dart';
import 'package:chess/services/settings.dart';
import 'package:chess/state/game_controller.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6?? 4.Qxf7#
const scholarsMate = ['e2e4', 'e7e5', 'f1c4', 'b8c6', 'd1h5', 'g8f6', 'h5f7'];

MatchRecord record({String id = 'g1', List<String> moves = scholarsMate, GameAnalysis? analysis}) => MatchRecord(
      id: id,
      startedAt: DateTime(2026, 11, 1, 9, 5),
      endedAt: DateTime(2026, 11, 1, 9, 9),
      startFen: Chess.initial.fen,
      playerSide: Side.white,
      moves: moves,
      result: '1-0',
      resultText: 'Checkmate. White wins.',
      endReason: 'Checkmate',
      opening: "King's Pawn Game",
      opponentElo: 1200,
      liveGrades: const {0: MoveQuality.book, 6: MoveQuality.best},
      analysis: analysis,
    );

/// Grades a game with the real search, run inline (no isolate).
GameAnalysis gradeInline(List<String> uci, {int timeMs = 150}) {
  final moves = uci.map((u) => Move.parse(u)!).toList();
  final positions = <Position>[Chess.initial];
  for (final m in moves) {
    positions.add(positions.last.play(m));
  }
  final results = [
    for (final p in positions)
      p.isGameOver ? null : SearchResult.fromJson(runSearch({'fen': p.fen, 'timeMs': timeMs, 'maxDepth': 6})),
  ];
  return gradeGame(positions: positions, moves: moves, results: results, timeMs: timeMs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('analysis', () {
    late GameAnalysis analysis;
    setUpAll(() => analysis = gradeInline(scholarsMate));

    test('grades every move of both players', () {
      expect(analysis.plies, hasLength(scholarsMate.length));
      expect(analysis.evalCp, hasLength(scholarsMate.length + 1));
      expect(analysis.firstMover, Side.white);
      expect(analysis.moverOf(5), Side.black);
    });

    test('flags the move that allows mate and rates the mate itself', () {
      expect(analysis.plies[5].quality, MoveQuality.blunder, reason: '3...Nf6?? allows Qxf7#');
      expect(analysis.plies[5].bestSan, isNot('Nf6'));
      expect(analysis.plies[6].quality.isBad, isFalse);
      expect(analysis.plies.first.quality, MoveQuality.book);
      expect(analysis.evalText.last, '1-0');
      expect(analysis.evalCp.last, greaterThan(2000));
    });

    test('accuracy and counts are split by side', () {
      expect(analysis.accuracy(Side.white)!, greaterThan(analysis.accuracy(Side.black)!));
      expect(analysis.counts(Side.black)[MoveQuality.blunder], 1);
      expect(analysis.counts(Side.white)[MoveQuality.blunder], isNull);
    });

    test('survives a JSON round trip', () {
      final back = GameAnalysis.fromJson(jsonDecode(jsonEncode(analysis.toJson())))!;
      expect(back.plies.map((p) => p.quality), analysis.plies.map((p) => p.quality));
      expect(back.evalCp, analysis.evalCp);
      expect(back.evalText, analysis.evalText);
      expect(back.plies[5].bestUci, analysis.plies[5].bestUci);
      expect(back.accuracy(Side.white), closeTo(analysis.accuracy(Side.white)!, 0.1));
    });

    test('the only legal move is graded forced', () {
      // The boxed-in king cannot move, so the a-pawn push is all Black has.
      final start = Chess.fromSetup(Setup.parseFen('7k/5Q2/8/p7/8/8/8/K7 b - - 0 1'));
      final move = Move.parse('a5a4')!;
      expect(start.legalMoves.values.fold(0, (n, d) => n + d.size), 1);
      final after = start.play(move);
      final results = [
        for (final p in [start, after]) SearchResult.fromJson(runSearch({'fen': p.fen, 'timeMs': 100, 'maxDepth': 4})),
      ];
      final graded = gradeGame(positions: [start, after], moves: [move], results: results, timeMs: 100);
      expect(graded.plies.single.quality, MoveQuality.forced);
    });
  });

  group('match record', () {
    test('round-trips through JSON with grades and analysis', () {
      final r = record(analysis: gradeInline(scholarsMate, timeMs: 80));
      final back = MatchRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(back.id, r.id);
      expect(back.moves, r.moves);
      expect(back.playerSide, Side.white);
      expect(back.winner, Side.white);
      expect(back.opponentElo, 1200);
      expect(back.liveGrades, r.liveGrades);
      expect(back.analysis!.plies, hasLength(scholarsMate.length));
    });

    test('replays only the legal prefix of corrupted moves', () {
      final r = record(moves: ['e2e4', 'e7e5', 'e1e8', 'g1f3']);
      expect(r.parsedMoves.map((m) => m.uci), ['e2e4', 'e7e5']);
    });

    test('exports PGN with headers, numbering, grades and evals', () {
      final pgn = record(analysis: gradeInline(scholarsMate, timeMs: 80)).toPgn();
      expect(pgn, contains('[White "You"]'));
      expect(pgn, contains('[Black "Computer (1200)"]'));
      expect(pgn, contains('[Result "1-0"]'));
      expect(pgn, contains('[Date "2026.11.01"]'));
      expect(pgn, isNot(contains('[FEN')));
      expect(pgn, contains('1. e4'));
      expect(pgn, contains('Nf6??'));
      expect(pgn, contains('Qxf7#'));
      expect(pgn, contains('[%eval'));
      expect(pgn.trim(), endsWith('1-0'));
      for (final line in pgn.split('\n')) {
        expect(line.length, lessThanOrEqualTo(80));
      }
    });

    test('PGN from a Black-to-move position starts with "N..."', () {
      final r = MatchRecord(
        id: 'b',
        startedAt: DateTime(2026),
        endedAt: DateTime(2026),
        startFen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        playerSide: Side.black,
        moves: const ['e7e5', 'g1f3'],
        result: '*',
        resultText: '',
        endReason: 'Abandoned',
      );
      final pgn = r.toPgn();
      expect(pgn, contains('[SetUp "1"]'));
      expect(pgn, contains('1... e5 2. Nf3 *'));
    });
  });

  group('match history', () {
    test('stores, replaces, reloads and deletes games', () async {
      final storage = MemoryMatchStorage();
      final history = MatchHistory(storage: storage);
      await history.upsert(record(id: 'a'));
      await history.upsert(MatchRecord.fromJson({
        ...record(id: 'b').toJson(),
        'endedAt': DateTime(2026, 11, 2).toIso8601String(),
      })!);
      expect(history.records.map((r) => r.id), ['b', 'a'], reason: 'newest first');

      await history.upsert(record(id: 'a', moves: const ['e2e4']));
      expect(history.records, hasLength(2));
      expect(history.byId('a')!.moves, ['e2e4']);

      final reloaded = MatchHistory(storage: storage);
      await reloaded.load();
      expect(reloaded.records.map((r) => r.id), ['b', 'a']);

      await reloaded.delete('b');
      expect(reloaded.records.map((r) => r.id), ['a']);
      await reloaded.clear();
      expect(reloaded.records, isEmpty);
      expect(jsonDecode(storage.data!), isEmpty);
    });

    test('a broken file loads as an empty history', () async {
      final history = MatchHistory(storage: MemoryMatchStorage('not json'));
      await history.load();
      expect(history.isLoaded, isTrue);
      expect(history.records, isEmpty);
    });
  });

  group('recording games', () {
    late SettingsController settings;
    late MatchHistory history;
    late GameController game;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'thinkTimeMs': 200});
      settings = await SettingsController.load();
      history = MatchHistory(storage: MemoryMatchStorage());
      game = GameController(
        engine: EngineService(),
        coach: CoachService(settings),
        settings: settings,
        matchHistory: history,
      );
    });

    Future<void> playOneMove() async {
      game.newGame(side: Side.white);
      await game.onPlayerMove(NormalMove(from: Square.e2, to: Square.e4));
      final sw = Stopwatch()..start();
      while (game.history.length < 2 && sw.elapsedMilliseconds < 20000) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(game.history.length, 2);
    }

    test('a resigned game is saved with its moves and result', () async {
      await playOneMove();
      game.resign();
      await history.load();
      await Future<void>.delayed(Duration.zero);
      final r = history.records.single;
      expect(r.id, game.matchId);
      expect(r.moves.first, 'e2e4');
      expect(r.moves, hasLength(2));
      expect(r.result, '0-1');
      expect(r.endReason, 'Resignation');
      expect(r.opponentElo, settings.eloRating);
    });

    test('an abandoned game is saved as unfinished, once', () async {
      await playOneMove();
      final id = game.matchId;
      game.recordAbandoned();
      game.newGame(side: Side.white);
      await Future<void>.delayed(Duration.zero);
      expect(history.records.single.id, id);
      expect(history.records.single.result, '*');
      expect(game.matchId, isNot(id));
    });

    test('nothing is saved when saving is off', () async {
      await settings.setSaveMatchHistory(false);
      await playOneMove();
      game.resign();
      await history.load();
      expect(history.records, isEmpty);
    });

    test('a resumed game keeps its match id', () async {
      await playOneMove();
      final saved = SavedGame.fromJson(jsonDecode(jsonEncode(game.snapshot().toJson())))!;
      expect(saved.matchId, game.matchId);
      final resumed = GameController(
        engine: EngineService(),
        coach: CoachService(settings),
        settings: settings,
        matchHistory: history,
      )..resumeGame(saved);
      expect(resumed.matchId, saved.matchId);
    });
  });
}
