import 'package:chess/coach/coach_service.dart';
import 'package:chess/engine/engine_service.dart';
import 'package:chess/services/settings.dart';
import 'package:chess/state/game_controller.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> waitFor(GameController game, bool Function() cond, {int timeoutMs = 20000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > timeoutMs) {
      fail('timed out waiting; phase=${game.phase} messages=${game.messages.map((m) => m.text).join(' | ')}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameController game;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'thinkTimeMs': 400, 'engineLevel': 8});
    final settings = await SettingsController.load();
    game = GameController(
      engine: EngineService(),
      coach: CoachService(settings),
      settings: settings,
    );
  });

  test('a normal move is graded and the opponent replies', () async {
    game.newGame(side: Side.white);
    await game.onPlayerMove(NormalMove(from: Square.e2, to: Square.e4));
    await waitFor(game, () => game.phase == GamePhase.playerTurn && game.history.length == 2);
    expect(game.history.first.san, 'e4');
    expect(game.history.first.review, isNotNull);
    expect(game.history.first.review!.quality.isBad, isFalse);
    expect(game.position.turn, Side.white);
  });

  test('a blunder pauses the game in strict mode and can be retried', () async {
    // Italian-style position where 3.Nxe5?? just loses a knight for a pawn.
    game.newGame(
      side: Side.white,
      startFen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
    );
    await game.onPlayerMove(NormalMove(from: Square.f3, to: Square.e5));
    await waitFor(game, () => game.phase == GamePhase.coaching || game.phase == GamePhase.playerTurn);
    expect(game.phase, GamePhase.coaching, reason: 'hanging the knight must trigger coaching');
    expect(game.pendingReview!.quality.isBad, isTrue);
    expect(game.messages.any((m) => m.kind == CoachMessageKind.coach), isTrue,
        reason: 'engine-only explanation should still be produced without an API key');
    // The explanation is written in words, not bare notation.
    final explanation = game.messages.lastWhere((m) => m.kind == CoachMessageKind.coach).text;
    expect(explanation, contains('knight'));
    expect(explanation, isNot(contains('Nxe5')));

    // The punishing line is replayed on the board automatically.
    expect(game.preview, isNotNull);
    expect(game.isPreviewing, isTrue);
    expect(game.canPlayerMove, isFalse);
    game.previewNext();
    expect(game.preview!.index, 1);
    expect(game.preview!.narration, contains('knight'));
    expect(game.displayedPosition.fen, isNot(game.position.fen));
    game.closePreview();
    expect(game.displayedPosition.fen, game.position.fen);

    final lenBefore = game.history.length;
    game.retryMove();
    expect(game.history.length, lenBefore - 1);
    expect(game.phase, GamePhase.playerTurn);
    expect(game.position.turn, Side.white);
    expect(game.retries, 1);

    // A sound developing move is accepted and the opponent answers.
    await game.onPlayerMove(NormalMove(from: Square.f1, to: Square.c4));
    await waitFor(game, () => game.phase == GamePhase.playerTurn && game.history.length == 2);
    expect(game.history.first.review!.quality.isBad, isFalse);
  });

  test('hints escalate from concept to arrow', () async {
    game.newGame(side: Side.white);
    await game.requestHint();
    expect(game.hintLevel, 1);
    await game.requestHint();
    expect(game.hintLevel, 2);
    expect(game.hintShapes, isNotEmpty);
    await game.requestHint();
    expect(game.hintLevel, 3);
    expect(game.messages.last.text, contains('The suggestion is'));
  });
}
