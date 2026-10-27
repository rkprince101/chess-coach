import 'package:chess/data/lessons_data.dart';
import 'package:chess/engine/search.dart';
import 'package:chess/models/lesson.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

String stripSuffix(String san) => san.replaceAll(RegExp(r'[+#]'), '');

void main() {
  for (final lesson in lessons) {
    group('lesson ${lesson.id}', () {
      for (final step in lesson.steps) {
        test('step "${step.title}" is well formed', () {
          final pos = Chess.fromSetup(Setup.parseFen(step.fen));
          expect(pos.isCheckmate || pos.isStalemate, isFalse, reason: 'position already over');

          switch (step.goal) {
            case GoalType.read:
            case GoalType.anyMove:
              break;
            case GoalType.playLine:
              expect(step.line, isNotEmpty);
              if (step.notes.isNotEmpty) {
                expect(step.notes.length, step.line.length,
                    reason: 'notes must align with line');
              }
              Position p = pos;
              for (final san in step.line) {
                final move = p.parseSan(san);
                expect(move, isNotNull, reason: 'illegal SAN $san in ${p.fen}');
                final (next, producedSan) = p.makeSan(move!);
                expect(stripSuffix(producedSan), stripSuffix(san),
                    reason: 'SAN spelling mismatch for $san');
                p = next;
              }
              // Tactics puzzles: the first move must be the engine's choice.
              if (lesson.category == LessonCategory.tactics ||
                  step.title == 'Underpromotion' ||
                  lesson.id == 'piece-values') {
                final r = Searcher(timeLimitMs: 3000, maxDepth: 5).search(pos);
                final expected = pos.parseSan(step.line.first)!;
                expect(r.bestMove!.uci, expected.uci,
                    reason: 'engine prefers ${pos.makeSan(r.bestMove!).$2} over ${step.line.first}');
              }
            case GoalType.reachSquare:
              expect(step.targetSquare, isNotNull);
              expect(step.maxMoves, isNotNull);
              expect(pos.board.pieceAt(step.targetSquare!), isNull,
                  reason: 'target square occupied');
            case GoalType.captureAll:
              final enemies = pos.board.bySide(pos.turn.opposite).size - 1;
              expect(enemies, greaterThan(0));
              expect(step.maxMoves, greaterThanOrEqualTo(enemies));
            case GoalType.checkmate:
              if (step.maxMoves == 1) {
                final r = Searcher(timeLimitMs: 2000, maxDepth: 3).search(pos);
                expect(isMateScore(r.score) && mateIn(r.score) == 1, isTrue,
                    reason: 'no mate in one: best ${r.bestMove?.uci} score ${r.score}');
              }
            case GoalType.promote:
              expect(pos.board.piecesOf(pos.turn, Role.pawn).isNotEmpty, isTrue);
          }
        });
      }
    });
  }

  test('stalemate trap step really has a stalemating move', () {
    final pos = Chess.fromSetup(Setup.parseFen('7k/8/6K1/5Q2/8/8/8/8 w - - 0 1'));
    final trap = pos.play(pos.parseSan('Qf7')!);
    expect(trap.isStalemate, isTrue);
  });
}
