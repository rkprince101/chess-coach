import 'dart:async';

import 'package:chessground/chessground.dart' show Arrow, Circle, Shape;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../coach/coach_service.dart';
import '../coach/facts.dart';
import '../engine/engine_service.dart';
import '../engine/search.dart';
import '../models/lesson.dart';
import '../services/settings.dart';
import '../voice/voice_service.dart';
import 'game_controller.dart' show CoachMessage, CoachMessageKind;

enum StepStatus { inProgress, solved, opponentThinking }

/// Runs one lesson step at a time: validates the student's moves against the
/// step's goal, plays scripted or engine replies, and hands out hints.
class LessonController extends ChangeNotifier {
  LessonController({
    required this.lesson,
    required this.engine,
    required this.coach,
    required this.settings,
    this.voice,
  }) {
    _loadStep(0);
  }

  final Lesson lesson;
  final EngineService engine;
  final CoachService coach;
  final SettingsController settings;
  final VoiceService? voice;

  bool get _speak => voice?.enabled ?? false;

  int stepIndex = 0;
  late Position position;
  Move? lastMove;
  StepStatus status = StepStatus.inProgress;
  final List<CoachMessage> messages = [];
  Set<Shape> shapes = {};
  int movesUsed = 0;
  int wrongAttempts = 0;
  int _lineIndex = 0;
  int _generation = 0;

  LessonStep get step => lesson.steps[stepIndex];
  bool get isLastStep => stepIndex == lesson.steps.length - 1;
  Side get studentSide => step.studentSide;
  bool get canMove =>
      status == StepStatus.inProgress && step.goal != GoalType.read && position.turn == studentSide;

  void _loadStep(int index) {
    _generation++;
    stepIndex = index;
    position = Chess.fromSetup(Setup.parseFen(step.fen));
    lastMove = null;
    status = StepStatus.inProgress;
    movesUsed = 0;
    wrongAttempts = 0;
    _lineIndex = 0;
    messages.clear();
    shapes = {
      for (final sq in step.highlights) Circle(color: const Color(0x99FFC107), orig: sq),
      for (final (a, b) in step.arrows) Arrow(color: const Color(0xAA2196F3), orig: a, dest: b),
    };
    if (step.goal == GoalType.read) status = StepStatus.solved;
    notifyListeners();
    if (_speak && settings.voiceLessons) {
      unawaited(voice!.say('${step.title}. ${step.text}', interrupt: true));
    }
  }

  void nextStep() {
    if (!isLastStep) _loadStep(stepIndex + 1);
  }

  void previousStep() {
    if (stepIndex > 0) _loadStep(stepIndex - 1);
  }

  void restartStep() => _loadStep(stepIndex);

  // ---------------------------------------------------------------------------

  Future<void> onMove(Move rawMove) async {
    if (!canMove) return;
    final move = rawMove is NormalMove ? position.normalizeMove(rawMove) : rawMove;
    if (!position.isLegal(move)) return;

    switch (step.goal) {
      case GoalType.read:
        return;
      case GoalType.anyMove:
        _apply(move);
        _solve();
      case GoalType.playLine:
        await _handleLineMove(move);
      case GoalType.reachSquare:
        _apply(move);
        movesUsed++;
        if (move.to == step.targetSquare) {
          _solve();
        } else if (movesUsed >= step.maxMoves!) {
          _fail('That used up your ${step.maxMoves} moves without reaching ${step.targetSquare!.name}. Let\'s reset and plan the route first.');
        } else {
          _passTurnBack();
          _say(CoachMessageKind.tip, '${step.maxMoves! - movesUsed} move left. Which square gets you to ${step.targetSquare!.name} from here?');
        }
      case GoalType.captureAll:
        final captured = position.board.pieceAt(move.to) != null;
        _apply(move);
        movesUsed++;
        final remaining = position.board.bySide(studentSide.opposite).size - 1;
        if (remaining == 0) {
          _solve();
        } else if (movesUsed >= step.maxMoves!) {
          _fail('Out of moves with $remaining pawn${remaining == 1 ? '' : 's'} left. Reset and look for the route that captures one pawn per move.');
        } else {
          _passTurnBack();
          _say(CoachMessageKind.tip,
              captured ? 'Got one. $remaining to go.' : 'No capture that time. $remaining left and ${step.maxMoves! - movesUsed} moves remaining.');
        }
      case GoalType.checkmate:
      case GoalType.promote:
        await _handleVersusEngineMove(move);
    }
  }

  Future<void> _handleLineMove(Move move) async {
    final expectedSan = step.line[_lineIndex];
    final expected = position.parseSan(expectedSan);
    if (expected == null || expected.uci != move.uci) {
      wrongAttempts++;
      final trial = position.playUnchecked(move);
      final san = position.makeSan(move).$2;
      String why;
      if (trial.isStalemate) {
        why = '$san is stalemate: Black would have no legal move and the game is drawn. Look for the mate instead.';
      } else if (wrongAttempts >= 2 && expected != null) {
        why = '$san is not it. Here is the move: $expectedSan. Play it and read why.';
        shapes = {..._staticShapes(), Arrow(color: const Color(0xAA4CAF50), orig: (expected as NormalMove).from, dest: expected.to)};
      } else {
        why = '$san is not the move we are after. ${_lineHint(expected)}';
      }
      _say(CoachMessageKind.warning, why);
      return;
    }

    _apply(move);
    final note = _noteAt(_lineIndex);
    _lineIndex++;
    if (note != null) _say(CoachMessageKind.coach, note);
    if (_lineIndex >= step.line.length) {
      _solve();
      return;
    }

    // Scripted opponent reply.
    status = StepStatus.opponentThinking;
    notifyListeners();
    final gen = _generation;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (gen != _generation) return;
    final reply = position.parseSan(step.line[_lineIndex]);
    if (reply == null) {
      _say(CoachMessageKind.error, 'Lesson data error: ${step.line[_lineIndex]} is not legal here.');
      return;
    }
    final replySan = step.line[_lineIndex];
    _apply(reply);
    final replyNote = _noteAt(_lineIndex);
    _lineIndex++;
    _say(CoachMessageKind.system, '${sideName(studentSide.opposite)} plays $replySan.${replyNote != null ? ' $replyNote' : ''}');
    status = StepStatus.inProgress;
    if (_lineIndex >= step.line.length) {
      _solve();
    }
    notifyListeners();
  }

  Future<void> _handleVersusEngineMove(Move move) async {
    _apply(move);
    movesUsed++;
    if (step.goal == GoalType.promote && move is NormalMove && move.promotion != null) {
      _solve();
      return;
    }
    if (position.isCheckmate) {
      if (step.goal == GoalType.checkmate) {
        _solve();
      } else {
        _solve(extra: 'Checkmate works too!');
      }
      return;
    }
    if (position.isStalemate) {
      _fail('Stalemate! The defending king had no legal move and was not in check, so it is a draw. Reset and leave the king a square until you can mate.');
      return;
    }
    if (position.isInsufficientMaterial) {
      _fail('Not enough material left to mate. Reset and keep your pieces.');
      return;
    }
    if (movesUsed >= step.maxMoves!) {
      _fail('That took more than ${step.maxMoves} moves. Reset and follow the technique in the lesson text.');
      return;
    }

    status = StepStatus.opponentThinking;
    notifyListeners();
    final gen = _generation;
    final SearchResult result;
    try {
      result = await engine.analyze(position.fen, timeMs: 400, maxDepth: 4);
    } catch (e) {
      if (gen != _generation) return;
      _say(CoachMessageKind.error, 'Engine error: $e');
      status = StepStatus.inProgress;
      notifyListeners();
      return;
    }
    if (gen != _generation) return;
    if (result.bestMove == null) {
      status = StepStatus.inProgress;
      notifyListeners();
      return;
    }
    _apply(result.bestMove!);
    status = StepStatus.inProgress;
    if (position.isCheckmate) {
      _fail('Your king was mated. Reset and try again.');
      return;
    }
    if (step.goal == GoalType.checkmate && movesUsed >= step.maxMoves! - 3 && movesUsed % 2 == 0) {
      _say(CoachMessageKind.tip, '${step.maxMoves! - movesUsed} moves left. Use a hint if you are stuck.');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------

  Future<void> requestHint() async {
    if (!canMove) return;
    switch (step.goal) {
      case GoalType.playLine:
        final expected = position.parseSan(step.line[_lineIndex]);
        if (expected is NormalMove) {
          shapes = {..._staticShapes(), Circle(color: const Color(0xAAFFC107), orig: expected.from)};
          _say(CoachMessageKind.tip, 'Hint: ${_lineHint(expected)}');
        }
      case GoalType.reachSquare:
      case GoalType.captureAll:
        final piece = _studentPieceSquare();
        if (piece != null) {
          final dests = position.legalMoves[piece] ?? SquareSet.empty;
          shapes = {
            ..._staticShapes(),
            for (final d in dests.squares) Circle(color: const Color(0x66FFC107), orig: d),
          };
          _say(CoachMessageKind.tip, 'These are every square your piece can reach right now. Which one lines up with the goal?');
        }
      case GoalType.checkmate:
      case GoalType.promote:
        final gen = _generation;
        final r = await engine.analyze(position.fen, timeMs: 800, maxDepth: 6);
        if (gen != _generation || r.bestMove == null) return;
        final best = r.bestMove as NormalMove;
        shapes = {..._staticShapes(), Arrow(color: const Color(0xAA4CAF50), orig: best.from, dest: best.to)};
        _say(CoachMessageKind.tip, 'Try ${position.makeSan(best).$2}. ${isMateScore(r.score) ? 'Mate in ${mateIn(r.score)} from here.' : ''}');
      case GoalType.read:
      case GoalType.anyMove:
        break;
    }
    notifyListeners();
  }

  /// Asks the AI coach to go deeper on this step.
  Future<void> explainMore() async {
    if (!settings.hasApiKey) {
      _say(CoachMessageKind.error, 'Add an AI API key in Settings to get AI explanations.');
      return;
    }
    final msg = CoachMessage(CoachMessageKind.coach, '', streaming: true);
    messages.add(msg);
    notifyListeners();
    final gen = _generation;
    try {
      await for (final chunk in coach.teachTopic(
        '${lesson.title}: ${step.title}',
        positionFen: position.fen,
        lessonText: step.text,
      )) {
        if (gen != _generation) return;
        msg.text += chunk;
        notifyListeners();
      }
    } catch (e) {
      if (msg.text.isEmpty) messages.remove(msg);
      _say(CoachMessageKind.error, e.toString());
    } finally {
      msg.streaming = false;
      notifyListeners();
      if (_speak && msg.text.isNotEmpty) unawaited(voice!.say(msg.text));
    }
  }

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty) return;
    _say(CoachMessageKind.user, q);
    if (!settings.hasApiKey) {
      _say(CoachMessageKind.error, 'Add an AI API key in Settings to chat with the coach.');
      return;
    }
    final msg = CoachMessage(CoachMessageKind.coach, '', streaming: true);
    messages.add(msg);
    notifyListeners();
    final gen = _generation;
    final context = GameContext(
      position: position,
      sanHistory: const [],
      playerSide: studentSide,
      openingName: null,
      analysis: null,
    );
    try {
      await for (final chunk in coach.ask('Lesson "${lesson.title}", step "${step.title}": ${step.text}\n\nQuestion: $q', context, const [])) {
        if (gen != _generation) return;
        msg.text += chunk;
        notifyListeners();
      }
    } catch (e) {
      if (msg.text.isEmpty) messages.remove(msg);
      _say(CoachMessageKind.error, e.toString());
    } finally {
      msg.streaming = false;
      notifyListeners();
      if (_speak && msg.text.isNotEmpty) unawaited(voice!.say(msg.text));
    }
  }

  // ---------------------------------------------------------------------------

  void _apply(Move move) {
    position = position.playUnchecked(move);
    lastMove = move;
    notifyListeners();
  }

  /// In single-side exercises the opponent never moves, so hand the turn back.
  void _passTurnBack() {
    final flipped = position.copyWith(turn: studentSide, epSquare: null);
    try {
      position = Chess.fromSetup(Setup.parseFen(flipped.fen), ignoreImpossibleCheck: true);
    } catch (_) {
      position = flipped;
    }
    notifyListeners();
  }

  Square? _studentPieceSquare() {
    final own = position.board.bySide(studentSide);
    final king = position.board.kingOf(studentSide);
    for (final sq in own.squares) {
      if (sq != king || own.size == 1) return sq;
    }
    return king;
  }

  String? _noteAt(int index) => index < step.notes.length ? step.notes[index] : null;

  String _lineHint(Move? expected) {
    if (expected is! NormalMove) return 'Look at the arrows and highlighted squares.';
    final piece = position.board.pieceAt(expected.from);
    if (piece == null) return 'Look at the highlighted squares.';
    final trial = position.playUnchecked(expected);
    final extra = trial.isCheckmate
        ? 'It is checkmate.'
        : trial.isCheck
            ? 'It gives check.'
            : position.board.pieceAt(expected.to) != null
                ? 'It captures something.'
                : '';
    return 'Try moving the ${roleName(piece.role)} on ${expected.from.name}. $extra'.trim();
  }

  Set<Shape> _staticShapes() => {
        for (final sq in step.highlights) Circle(color: const Color(0x99FFC107), orig: sq),
        for (final (a, b) in step.arrows) Arrow(color: const Color(0xAA2196F3), orig: a, dest: b),
      };

  void _solve({String? extra}) {
    status = StepStatus.solved;
    final text = [
      'Solved!',
      ?extra,
      ?step.successText,
      if (!isLastStep) 'Press Next to continue.' else 'That completes this lesson.',
    ].join(' ');
    _say(CoachMessageKind.praise, text);
  }

  void _fail(String text) {
    _say(CoachMessageKind.warning, text);
    final gen = _generation;
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (gen != _generation) return;
      final keep = List<CoachMessage>.from(messages);
      _loadStep(stepIndex);
      messages.addAll(keep.where((m) => m.kind == CoachMessageKind.warning).take(1));
      notifyListeners();
    });
  }

  void _say(CoachMessageKind kind, String text) {
    messages.add(CoachMessage(kind, text));
    while (messages.length > 40) {
      messages.removeAt(0);
    }
    notifyListeners();
    if (_speak && kind != CoachMessageKind.user && kind != CoachMessageKind.error) {
      unawaited(voice!.say(text, interrupt: kind == CoachMessageKind.warning));
    }
  }
}
