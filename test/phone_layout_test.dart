import 'package:chess/coach/coach_service.dart';
import 'package:chess/data/lessons_data.dart';
import 'package:chess/engine/engine_service.dart';
import 'package:chess/main.dart';
import 'package:chess/services/settings.dart';
import 'package:chess/state/game_controller.dart';
import 'package:chess/ui/screens/lesson_screen.dart';
import 'package:chess/ui/screens/play_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pixel 7-ish logical size. Any RenderFlex overflow fails these tests.
const phone = Size(411, 923);
const phoneLandscape = Size(923, 411);

Future<SettingsController> settings() async {
  SharedPreferences.setMockInitialValues({'thinkTimeMs': 300, 'engineLevel': 8});
  return SettingsController.load();
}

Widget wrap(SettingsController s, Widget child, {EngineService? engine}) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: s),
        Provider(create: (_) => engine ?? EngineService()),
        Provider(create: (_) => CoachService(s)),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  testWidgets('home, lessons, a lesson and settings fit a phone', (tester) async {
    final s = await settings();
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChessCoachApp(settings: s));
    await tester.pumpAndSettle();
    expect(find.text('Play & Learn'), findsOneWidget);

    await tester.tap(find.text('Lessons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The pawn'));
    await tester.pumpAndSettle();
    expect(find.text('Marching forward'), findsOneWidget);
    expect(find.text('Hint'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Settings'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Groq API key'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
  });

  testWidgets('a long lesson step fits a phone in portrait and landscape', (tester) async {
    final s = await settings();
    final lesson = lessons.firstWhere((l) => l.id == 'castling');
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    tester.view.physicalSize = phone;
    await tester.pumpWidget(wrap(s, LessonScreen(lesson: lesson)));
    await tester.pumpAndSettle();
    expect(find.text('Kingside'), findsOneWidget);

    tester.view.physicalSize = phoneLandscape;
    await tester.pumpAndSettle();
    expect(find.text('Kingside'), findsOneWidget);
  });

  testWidgets('play screen with coaching prompt and preview fits a phone', (tester) async {
    final s = await settings();
    final engine = EngineService();
    final game = GameController(engine: engine, coach: CoachService(s), settings: s);
    addTearDown(game.dispose);
    addTearDown(engine.dispose);
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(s, PlayScreen(controller: game), engine: engine));
    await tester.pumpAndSettle();

    // Drive a real blunder through the engine (needs real async).
    await tester.runAsync(() async {
      game.newGame(
        side: Side.white,
        startFen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
      );
      await game.onPlayerMove(NormalMove(from: Square.f3, to: Square.e5));
      final sw = Stopwatch()..start();
      while (game.phase != GamePhase.coaching && sw.elapsedMilliseconds < 20000) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(game.phase, GamePhase.coaching);
    expect(game.preview, isNotNull);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Back to game'), findsOneWidget);
    expect(find.textContaining(RegExp('Blunder|Mistake|Inaccuracy')), findsWidgets);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(game.phase, GamePhase.playerTurn);
    expect(game.preview, isNull);
    expect(find.text('Hint'), findsOneWidget);

    // Landscape phone switches to the side-by-side layout without overflow.
    tester.view.physicalSize = phoneLandscape;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hint'), findsOneWidget);
  });
}
