import 'package:chess/engine/engine_service.dart';
import 'package:chess/models/move_quality.dart';
import 'package:chess/services/match_history.dart';
import 'package:chess/services/settings.dart';
import 'package:chess/ui/screens/history_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in const [Size(1400, 900), Size(390, 844)]) {
    testWidgets('saved game opens and analyses at ${size.width.toInt()}px', (tester) async {
      SharedPreferences.setMockInitialValues({'analysisStrength': 'quick'});
      final settings = await SettingsController.load();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final history = MatchHistory(storage: MemoryMatchStorage());
      await history.upsert(MatchRecord(
        id: 'g1',
        startedAt: DateTime(2026, 11, 1, 9, 5),
        endedAt: DateTime(2026, 11, 1, 9, 9),
        startFen: Chess.initial.fen,
        playerSide: Side.black,
        moves: const ['e2e4', 'e7e5', 'f1c4', 'b8c6', 'd1h5', 'g8f6', 'h5f7'],
        result: '1-0',
        resultText: 'Checkmate. White wins.',
        endReason: 'Checkmate',
        opponentElo: 1200,
        liveGrades: const {5: MoveQuality.blunder},
      ));
      final engine = EngineService();
      addTearDown(engine.dispose);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: history),
          Provider.value(value: engine),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('You lost by checkmate'), findsOneWidget);
      expect(find.textContaining('Black vs computer (1200)'), findsOneWidget);

      await tester.tap(find.text('You lost by checkmate'));
      await tester.pumpAndSettle();
      expect(find.text('Game analysis'), findsOneWidget);
      // Before analysis, the coach's live grade is already on the move.
      final panel = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(find.byIcon(MoveQuality.blunder.icon), 200, scrollable: panel);
      expect(find.byIcon(MoveQuality.blunder.icon), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Analyse game'), -200, scrollable: panel);

      await tester.tap(find.text('Analyse game'));
      await tester.runAsync(() async {
        final sw = Stopwatch()..start();
        while (history.byId('g1')!.analysis == null && sw.elapsedMilliseconds < 30000) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('(you) accuracy'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Move grades'), 200, scrollable: panel);
      expect(find.text('Move grades'), findsOneWidget);
      expect(history.byId('g1')!.analysis, isNotNull, reason: 'analysis is saved with the game');
      expect(tester.takeException(), isNull);

      // Step back to Black's blunder.
      await tester.tap(find.byTooltip('Previous move'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('Best was'), -200, scrollable: panel);
      expect(find.textContaining('Best was'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
