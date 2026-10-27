import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart' show Arrow, Circle, Shape;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../coach/coach_service.dart';
import '../coach/facts.dart';
import '../coach/opening_book.dart' as book;
import '../engine/engine_service.dart';
import '../engine/evaluator.dart' show pieceValue;
import '../engine/search.dart';
import '../models/move_quality.dart';
import '../services/saved_game.dart';
import '../services/settings.dart';
import '../voice/speech_text.dart';
import '../voice/voice_service.dart';

enum GamePhase { playerTurn, analyzing, coaching, engineThinking, gameOver }

enum CoachMessageKind { coach, tip, warning, praise, user, error, system }

class CoachMessage {
  CoachMessage(this.kind, this.text, {this.streaming = false});

  final CoachMessageKind kind;
  String text;
  bool streaming;
}

class HistoryEntry {
  HistoryEntry({required this.before, required this.move, required this.san, required this.after});

  final Position before;
  final Move move;
  final String san;
  final Position after;
  MoveReview? review;
}

/// A variation being replayed on the board so the student can *see* what
/// happens instead of reading notation.
class LinePreview {
  LinePreview({
    required this.title,
    required this.start,
    required this.moves,
    required this.viewer,
  });

  final String title;
  final Position start;
  final List<Move> moves;
  final Side viewer;

  /// How many moves of [moves] are currently shown.
  int index = 0;
  bool autoPlaying = true;

  final List<Position> _positions = [];

  Position get position {
    if (_positions.isEmpty) {
      var p = start;
      _positions.add(p);
      for (final m in moves) {
        p = p.playUnchecked(m);
        _positions.add(p);
      }
    }
    return _positions[index];
  }

  Move? get lastMove => index == 0 ? null : moves[index - 1];
  bool get atStart => index == 0;
  bool get atEnd => index >= moves.length;

  /// Plain-English description of the move just shown.
  String get narration {
    if (index == 0) return 'Starting position of the line. Press play or step forward.';
    position; // ensure cache
    return friendlyMove(_positions[index - 1], moves[index - 1], viewer: viewer);
  }

  Set<Shape> get shapes {
    final m = lastMove;
    if (m is! NormalMove) return {};
    return {Arrow(color: const Color(0xCCE53935), orig: m.from, dest: m.to)};
  }
}

/// Drives a "play and learn" game: the student's moves are graded by the
/// engine, questionable ones are explained by the coach with an offer to
/// retry, and the engine opponent answers at the chosen skill level.
class GameController extends ChangeNotifier {
  GameController({
    required this.engine,
    required this.coach,
    required this.settings,
    this.voice,
  });

  final EngineService engine;
  final CoachService coach;
  final SettingsController settings;

  /// Optional spoken coach; null in tests and on the web.
  final VoiceService? voice;

  bool get _speak => voice?.enabled ?? false;
  bool get _speakPreview => _speak && settings.voicePreview;
  static const _spokenKinds = {
    CoachMessageKind.coach,
    CoachMessageKind.tip,
    CoachMessageKind.warning,
    CoachMessageKind.praise,
  };
  final math.Random _random = math.Random();

  Position position = Chess.initial;
  final List<HistoryEntry> history = [];
  Side playerSide = Side.white;
  GamePhase phase = GamePhase.playerTurn;
  String? gameOverText;

  /// Winner of a finished game (null for a draw) and how it ended, e.g.
  /// "Checkmate". Only meaningful in [GamePhase.gameOver].
  Side? winner;
  String? endReason;

  /// Index into [messages] of the game-over notice, so the end-of-game
  /// summary can be told apart from earlier coach messages.
  int? gameOverMessageIndex;

  /// Analysis of the live position, used for hints and the evaluation bar.
  SearchResult? liveAnalysis;
  MoveReview? pendingReview;
  final List<CoachMessage> messages = [];
  final List<Map<String, dynamic>> _chatHistory = [];
  Set<Shape> hintShapes = {};
  int hintLevel = 0;
  int retries = 0;

  /// Index into [history] when browsing earlier positions; null means live.
  int? viewIndex;

  /// A line being replayed on the board, or null.
  LinePreview? preview;
  Timer? _previewTimer;

  final Set<String> _shownTips = {};
  int _generation = 0;
  bool _summaryRequested = false;

  // ---------------------------------------------------------------------------
  // Derived state

  List<String> get sanHistory => history.map((h) => h.san).toList();
  String? get openingName => book.openingName(sanHistory);
  bool get isViewingHistory => viewIndex != null;
  bool get isPreviewing => preview != null;
  Position get displayedPosition {
    final pv = preview;
    if (pv != null) return pv.position;
    return viewIndex == null ? position : history[viewIndex!].after;
  }

  Move? get displayedLastMove {
    final pv = preview;
    if (pv != null) return pv.lastMove;
    return viewIndex == null ? (history.isEmpty ? null : history.last.move) : history[viewIndex!].move;
  }

  /// Shapes to draw for the displayed position.
  Set<Shape> get displayedShapes {
    final pv = preview;
    if (pv != null) return pv.shapes;
    return viewIndex == null ? hintShapes : const {};
  }

  bool get canPlayerMove =>
      phase == GamePhase.playerTurn && viewIndex == null && preview == null && position.turn == playerSide;
  bool get coachEnabled => settings.coachEnabled && settings.coachMode != CoachMode.off;

  /// Evaluation in centipawns from White's point of view for the eval bar.
  int? get evalCpWhite {
    final a = liveAnalysis;
    if (a == null || a.fen != position.fen) return null;
    final cp = scoreToCp(a.score);
    return position.turn == Side.white ? cp : -cp;
  }

  String? get evalText {
    final a = liveAnalysis;
    if (a == null || a.fen != position.fen) return null;
    return formatScore(a.score, position.turn);
  }

  List<MoveReview> get playerReviews => [
        for (final h in history)
          if (h.before.turn == playerSide && h.review != null) h.review!,
      ];

  double get accuracy => accuracyFromLosses(playerReviews.map((r) => r.winPercentLoss));

  // ---------------------------------------------------------------------------
  // Game lifecycle

  void newGame({Side? side, String? startFen}) {
    _reset(side: side, startFen: startFen);
    _say(CoachMessageKind.system,
        'New game. You play ${sideName(playerSide)}. I will watch every move and step in when something can be improved. Ask me anything at any time.');
    if (!settings.hasApiKey && coachEnabled) {
      _say(CoachMessageKind.warning,
          'No AI API key set, so explanations will be engine-only. Add a Grok or Claude key in Settings for full coaching.');
    }
    notifyListeners();
    _kickOff();
  }

  /// Restores a game saved with [snapshot], replaying its moves without
  /// re-reviewing them.
  void resumeGame(SavedGame saved) {
    _reset(side: saved.playerSide, startFen: saved.startFen);
    for (final uci in saved.moves) {
      final move = Move.parse(uci);
      if (move == null || !position.isLegal(move)) break;
      final (after, san) = position.makeSan(move);
      history.add(HistoryEntry(before: position, move: move, san: san, after: after));
      position = after;
    }
    _say(CoachMessageKind.system,
        'Welcome back! Your saved game is restored. You play ${sideName(playerSide)}.');
    notifyListeners();
    if (position.isGameOver) {
      _finishOnBoard(position);
    } else {
      _kickOff();
    }
  }

  /// The current game in a form that can be stored and resumed later.
  SavedGame snapshot() => SavedGame(
        startFen: history.isEmpty ? position.fen : history.first.before.fen,
        playerSide: playerSide,
        moves: [for (final h in history) h.move.uci],
      );

  /// Whether leaving now would lose a game worth keeping.
  bool get isInProgress => history.isNotEmpty && phase != GamePhase.gameOver;

  void _kickOff() {
    if (position.turn != playerSide) {
      _engineTurn();
    } else {
      _prepareLiveAnalysis();
    }
  }

  void _reset({Side? side, String? startFen}) {
    _generation++;
    voice?.stop();
    playerSide = side ?? (settings.playAsWhite ? Side.white : Side.black);
    position = startFen == null ? Chess.initial : Chess.fromSetup(Setup.parseFen(startFen));
    history.clear();
    messages.clear();
    _chatHistory.clear();
    _shownTips.clear();
    hintShapes = {};
    hintLevel = 0;
    retries = 0;
    viewIndex = null;
    closePreview();
    pendingReview = null;
    liveAnalysis = null;
    gameOverText = null;
    winner = null;
    endReason = null;
    gameOverMessageIndex = null;
    _summaryRequested = false;
    phase = GamePhase.playerTurn;
  }

  void resign() {
    if (phase == GamePhase.gameOver) return;
    _finishGame(
      '${sideName(playerSide)} resigned. ${sideName(playerSide.opposite)} wins.',
      winner: playerSide.opposite,
      reason: 'Resignation',
    );
  }

  // ---------------------------------------------------------------------------
  // Player move handling

  Future<void> onPlayerMove(Move rawMove) async {
    if (!canPlayerMove) return;
    final move = rawMove is NormalMove ? position.normalizeMove(rawMove) : rawMove;
    if (!position.isLegal(move)) return;

    final gen = _generation;
    final before = position;
    final (after, san) = before.makeSan(move);
    final entry = HistoryEntry(before: before, move: move, san: san, after: after);
    history.add(entry);
    position = after;
    hintShapes = {};
    hintLevel = 0;
    phase = GamePhase.analyzing;
    unawaited(HapticFeedback.selectionClick());
    notifyListeners();

    if (after.isGameOver) {
      await _reviewMove(entry, gen);
      if (gen != _generation) return;
      _finishOnBoard(after);
      return;
    }

    if (!coachEnabled) {
      phase = GamePhase.engineThinking;
      notifyListeners();
      // Still grade silently so the post-game summary has data.
      unawaited(_reviewMove(entry, gen));
      await _engineTurn();
      return;
    }

    final review = await _reviewMove(entry, gen);
    if (gen != _generation || review == null) return;

    if (review.quality.needsCoaching) {
      if (settings.coachMode == CoachMode.strict) {
        pendingReview = review;
        phase = GamePhase.coaching;
        unawaited(HapticFeedback.mediumImpact());
        notifyListeners();
        if (settings.autoPreview && review.punishingMoves.isNotEmpty) showPunishment(review);
        await _explain(review, before, gen);
        return;
      }
      // Relaxed: explain in the background while the game continues.
      unawaited(_explain(review, before, gen));
    } else {
      _acknowledgeGoodMove(review, before, gen);
    }

    phase = GamePhase.engineThinking;
    notifyListeners();
    await _engineTurn();
  }

  /// Student decided to keep a flagged move.
  Future<void> keepMove() async {
    if (phase != GamePhase.coaching) return;
    closePreview();
    pendingReview = null;
    phase = GamePhase.engineThinking;
    _say(CoachMessageKind.system, 'Alright, we play on. Watch how the opponent responds.');
    notifyListeners();
    await _engineTurn();
  }

  /// Student takes back the flagged move to try a different approach.
  void retryMove() {
    if (phase != GamePhase.coaching || history.isEmpty) return;
    voice?.stop();
    closePreview();
    final last = history.removeLast();
    position = last.before;
    pendingReview = null;
    retries++;
    phase = GamePhase.playerTurn;
    _say(CoachMessageKind.system,
        'Move taken back. Take your time: what is the opponent threatening, and what are your pieces doing?');
    notifyListeners();
    _prepareLiveAnalysis();
  }

  /// Take back the last full move (student + opponent) at any quiet moment.
  void takeBackFullMove() {
    if (phase != GamePhase.playerTurn && phase != GamePhase.gameOver) return;
    if (history.isEmpty) return;
    _generation++;
    closePreview();
    // Remove opponent's reply (if any) and the student's move.
    while (history.isNotEmpty && history.last.before.turn != playerSide) {
      history.removeLast();
    }
    if (history.isNotEmpty) history.removeLast();
    position = history.isEmpty ? Chess.initial : history.last.after;
    phase = GamePhase.playerTurn;
    gameOverText = null;
    winner = null;
    endReason = null;
    gameOverMessageIndex = null;
    viewIndex = null;
    hintShapes = {};
    hintLevel = 0;
    _say(CoachMessageKind.system, 'Took back the last move pair. Your move.');
    notifyListeners();
    if (position.turn != playerSide) {
      _engineTurn();
    } else {
      _prepareLiveAnalysis();
    }
  }

  // ---------------------------------------------------------------------------
  // Line previews (the coach "moves the pieces")

  /// Replays the opponent's best reply line after a flagged move.
  void showPunishment(MoveReview review) {
    if (review.punishingMoves.isEmpty) return;
    _startPreview(LinePreview(
      title: 'What happens after your move',
      start: review.after,
      moves: review.punishingMoves,
      viewer: playerSide,
    ));
  }

  /// Replays the engine's preferred line from the position before the move.
  void showBetterLine(MoveReview review) {
    if (review.bestMoves.isEmpty) return;
    _startPreview(LinePreview(
      title: 'A better idea instead',
      start: review.before,
      moves: review.bestMoves,
      viewer: playerSide,
    ));
  }

  /// Replays the engine's best line from the live position (used by hints).
  void showBestLineFromHere(SearchResult analysis) {
    if (analysis.pv.isEmpty) return;
    _startPreview(LinePreview(
      title: 'The idea the engine likes here',
      start: position,
      moves: _legalPrefix(position, analysis.pv, 6),
      viewer: playerSide,
    ));
  }

  void _startPreview(LinePreview pv) {
    _previewTimer?.cancel();
    preview = pv;
    viewIndex = null;
    notifyListeners();
    _schedulePreviewStep();
  }

  void _schedulePreviewStep() {
    _previewTimer?.cancel();
    final pv = preview;
    if (pv == null || !pv.autoPlaying) return;
    _previewTimer = Timer(Duration(milliseconds: pv.atStart ? 700 : 1500), () async {
      final current = preview;
      if (current == null || !current.autoPlaying) return;
      if (current.atEnd) {
        current.autoPlaying = false;
        notifyListeners();
        return;
      }
      current.index++;
      notifyListeners();
      if (_speakPreview) {
        // Let the narration finish before the next piece moves.
        await voice!.say(current.narration, interrupt: true);
        if (preview != current || !current.autoPlaying) return;
      }
      _schedulePreviewStep();
    });
  }

  void previewNext() {
    final pv = preview;
    if (pv == null || pv.atEnd) return;
    pv.autoPlaying = false;
    _previewTimer?.cancel();
    pv.index++;
    notifyListeners();
    if (_speakPreview) unawaited(voice!.say(pv.narration, interrupt: true));
  }

  void previewPrevious() {
    final pv = preview;
    if (pv == null || pv.atStart) return;
    pv.autoPlaying = false;
    _previewTimer?.cancel();
    pv.index--;
    notifyListeners();
  }

  void previewTogglePlay() {
    final pv = preview;
    if (pv == null) return;
    if (pv.autoPlaying) {
      pv.autoPlaying = false;
      _previewTimer?.cancel();
    } else {
      if (pv.atEnd) pv.index = 0;
      pv.autoPlaying = true;
      _schedulePreviewStep();
    }
    notifyListeners();
  }

  void closePreview() {
    _previewTimer?.cancel();
    _previewTimer = null;
    if (preview == null) return;
    if (_speakPreview) voice?.stop();
    preview = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Hints and questions

  Future<void> requestHint() async {
    if (!canPlayerMove) return;
    final gen = _generation;
    final analysis = await _ensureLiveAnalysis();
    if (gen != _generation || analysis == null || analysis.bestMove == null) return;
    final best = analysis.bestMove as NormalMove;
    hintLevel = (hintLevel + 1).clamp(1, 3);

    switch (hintLevel) {
      case 1:
        hintShapes = {};
        if (settings.hasApiKey && coachEnabled) {
          await _stream(coach.conceptHint(_context()), CoachMessageKind.tip, gen);
        } else {
          _say(CoachMessageKind.tip, _localConceptHint(analysis));
        }
      case 2:
        hintShapes = {Circle(color: const Color(0xAAFFC107), orig: best.from)};
        final piece = position.board.pieceAt(best.from)!;
        _say(CoachMessageKind.tip,
            'Second hint: look at your ${roleName(piece.role)} on ${best.from.name} (circled). Where can it go to do the most?');
      default:
        hintShapes = {Arrow(color: const Color(0xAA4CAF50), orig: best.from, dest: best.to)};
        _say(CoachMessageKind.tip,
            'The suggestion is: ${friendlyMove(position, best, viewer: playerSide)} (the green arrow). Press "Show me" to watch how the next few moves could go.');
    }
    notifyListeners();
  }

  /// Plays the hinted line on the board (available after the third hint).
  Future<void> showHintLine() async {
    final analysis = await _ensureLiveAnalysis();
    if (analysis == null) return;
    showBestLineFromHere(analysis);
  }

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty) return;
    final gen = _generation;
    _say(CoachMessageKind.user, q);
    if (!settings.hasApiKey) {
      _say(CoachMessageKind.error, 'Add an AI API key in Settings to chat with the coach.');
      return;
    }
    final analysis = await _ensureLiveAnalysis();
    if (gen != _generation) return;
    final context = _context(analysis: analysis);
    final answer = await _stream(coach.ask(q, context, _chatHistory), CoachMessageKind.coach, gen);
    if (answer != null) {
      _chatHistory
        ..add({'role': 'user', 'content': q})
        ..add({'role': 'assistant', 'content': answer});
      if (_chatHistory.length > 12) _chatHistory.removeRange(0, 2);
    }
  }

  void viewPly(int? index) {
    viewIndex = index;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internals

  Future<MoveReview?> _reviewMove(HistoryEntry entry, int gen) async {
    final before = entry.before;
    final after = entry.after;
    final time = settings.thinkTimeMs;
    SearchResult? analysisBefore;
    SearchResult? analysisAfter;
    try {
      analysisBefore = await engine.analyze(before.fen, timeMs: time);
      if (!after.isGameOver) analysisAfter = await engine.analyze(after.fen, timeMs: time);
    } catch (e) {
      _say(CoachMessageKind.error, 'Engine error: $e');
      return null;
    }
    if (gen != _generation) return null;

    final bestScore = analysisBefore.score;
    final int playedScore;
    if (after.isCheckmate) {
      playedScore = mateScore - 1;
    } else if (after.isGameOver) {
      playedScore = 0;
    } else {
      playedScore = -analysisAfter!.score;
    }
    final bestMove = analysisBefore.bestMove;
    final playedIsBest = bestMove != null && bestMove.uci == entry.move.uci;
    var quality = classifyMove(
      bestScore: bestScore,
      playedScore: playedScore,
      playedIsBest: playedIsBest,
    );
    if (!quality.isBad && book.isBookLine(sanHistory.take(history.indexOf(entry) + 1).toList())) {
      quality = MoveQuality.book;
    }
    final loss = (winPercent(scoreToCp(bestScore)) - winPercent(scoreToCp(playedScore))).clamp(0.0, 100.0);

    final review = MoveReview(
      before: before,
      after: after,
      move: entry.move,
      san: entry.san,
      quality: quality,
      bestMove: bestMove,
      bestSan: bestMove == null ? null : before.makeSan(bestMove).$2,
      bestLine: lineToSan(before, analysisBefore.pv),
      evalBefore: formatScore(bestScore, before.turn),
      evalAfter: formatScore(playedScore, before.turn),
      winPercentLoss: loss,
      punishingLine: analysisAfter == null ? '' : lineToSan(after, analysisAfter.pv, maxPlies: 6),
      bestMoves: _legalPrefix(before, analysisBefore.pv, 6),
      punishingMoves: analysisAfter == null ? const [] : _legalPrefix(after, analysisAfter.pv, 6),
    );
    entry.review = review;
    if (analysisAfter != null) liveAnalysis = analysisAfter;
    notifyListeners();
    return review;
  }

  Future<void> _explain(MoveReview review, Position before, int gen) async {
    final watch = review.punishingMoves.isNotEmpty
        ? ' Watch the board: the red arrows show how the opponent can punish it.'
        : '';
    final header = '${review.quality.label}: ${friendlyMove(review.before, review.move, viewer: playerSide)}. '
        'The evaluation went from ${review.evalBefore} to ${review.evalAfter} '
        '(plus is good for White, minus for Black).$watch';
    _say(CoachMessageKind.warning, header);
    if (settings.hasApiKey) {
      final context = GameContext(
        position: before,
        sanHistory: sanHistory.take(history.indexOf(_entryFor(review))).toList(),
        playerSide: playerSide,
        openingName: openingName,
        analysis: null,
      );
      await _stream(coach.explainMistake(review, context), CoachMessageKind.coach, gen);
    } else {
      _say(CoachMessageKind.coach, _localExplanation(review));
    }
  }

  HistoryEntry _entryFor(MoveReview review) =>
      history.firstWhere((h) => h.review == review, orElse: () => history.last);

  void _acknowledgeGoodMove(MoveReview review, Position before, int gen) {
    if (review.quality == MoveQuality.book) {
      final name = openingName;
      if (name != null && _shownTips.add('book:$name')) {
        _say(CoachMessageKind.tip, 'Book move. You are playing the $name.');
      }
      return;
    }
    final notable = review.quality == MoveQuality.best &&
        (review.after.isCheck ||
            before.board.pieceAt(review.move.to) != null ||
            review.san.contains('O-O'));
    if (notable && settings.hasApiKey && _random.nextDouble() < 0.6) {
      unawaited(_stream(coach.praiseMove(review, _context(position: before)), CoachMessageKind.praise, gen));
    } else if (review.quality == MoveQuality.best) {
      _say(CoachMessageKind.praise,
          'Best move. ${friendlyMove(review.before, review.move, viewer: playerSide)}: exactly what the position asked for.');
    }
  }

  Future<void> _engineTurn() async {
    final gen = _generation;
    phase = GamePhase.engineThinking;
    notifyListeners();
    final SearchResult result;
    try {
      result = await engine.analyze(position.fen, timeMs: settings.thinkTimeMs);
    } catch (e) {
      if (gen != _generation) return;
      _say(CoachMessageKind.error, 'Engine error: $e');
      phase = GamePhase.playerTurn;
      notifyListeners();
      return;
    }
    if (gen != _generation) return;
    if (result.bestMove == null) {
      _finishOnBoard(position);
      return;
    }
    final move = pickMoveForLevel(result, settings.engineLevel, _random);
    final before = position;
    final (after, san) = before.makeSan(move);
    history.add(HistoryEntry(before: before, move: move, san: san, after: after));
    position = after;
    notifyListeners();

    if (after.isGameOver) {
      _finishOnBoard(after);
      return;
    }
    phase = GamePhase.playerTurn;
    notifyListeners();
    _localTipsAfterOpponentMove();
    _prepareLiveAnalysis();
  }

  void _prepareLiveAnalysis() {
    final gen = _generation;
    final fen = position.fen;
    engine.analyze(fen, timeMs: settings.thinkTimeMs).then((r) {
      if (gen != _generation || position.fen != fen) return;
      liveAnalysis = r;
      notifyListeners();
    }).catchError((_) {});
  }

  Future<SearchResult?> _ensureLiveAnalysis() async {
    final a = liveAnalysis;
    if (a != null && a.fen == position.fen) return a;
    try {
      final r = await engine.analyze(position.fen, timeMs: settings.thinkTimeMs);
      if (position.fen == r.fen) liveAnalysis = r;
      return r;
    } catch (_) {
      return null;
    }
  }

  void _localTipsAfterOpponentMove() {
    if (!coachEnabled) return;
    if (position.isCheck && _shownTips.add('check')) {
      _say(CoachMessageKind.tip,
          'Check! Your king is attacked. You must respond: move the king, block the line, or capture the attacker.');
    }
    final threats = hangingPieces(position, playerSide);
    if (threats.isNotEmpty) {
      final t = threats.first;
      if (pieceValue(t.piece.role) >= 300 && _shownTips.add('threat:${t.square.name}:${t.piece.role.name}')) {
        _say(CoachMessageKind.warning,
            'Careful: your ${roleName(t.piece.role)} on ${t.square.name} is under attack${t.undefended ? ' and nothing defends it' : ' by a cheaper piece'}. Deal with that before anything else.');
      }
    }
    final special = specialMoves(position);
    if (special.canCastle && _shownTips.add('castle')) {
      _say(CoachMessageKind.tip,
          'You can castle now: move the king two squares toward the rook and the rook hops over. It tucks the king away and connects the rooks. Usually worth doing early.');
    }
    if (special.canEnPassant && _shownTips.add('ep')) {
      _say(CoachMessageKind.tip,
          'En passant is available! The enemy pawn just advanced two squares past your pawn; this move only, you may capture it as if it had moved one square.');
    }
    if (special.canPromote && _shownTips.add('promote')) {
      _say(CoachMessageKind.tip,
          'A pawn can reach the last rank. Promote it, almost always to a queen, unless a knight gives a check or fork the queen cannot.');
    }
    final obs = openingObservations(
      history.map((h) => (h.before, h.move)).toList(),
      playerSide,
    );
    for (final o in obs) {
      if (_shownTips.add('obs:$o')) _say(CoachMessageKind.tip, o);
    }
  }

  void _finishOnBoard(Position pos) {
    final (text, winner, reason) = _describeOutcome(pos);
    _finishGame(text, winner: winner, reason: reason);
  }

  void _finishGame(String text, {required Side? winner, required String reason}) {
    phase = GamePhase.gameOver;
    gameOverText = text;
    this.winner = winner;
    endReason = reason;
    gameOverMessageIndex = messages.length;
    unawaited(HapticFeedback.heavyImpact());
    if (_speak) unawaited(voice!.say('Game over. $text', interrupt: true));
    _say(CoachMessageKind.system, 'Game over: $text');
    notifyListeners();
    if (!_summaryRequested && coachEnabled && playerReviews.isNotEmpty) {
      _summaryRequested = true;
      final gen = _generation;
      if (settings.hasApiKey) {
        unawaited(_stream(
          coach.gameSummary(
            context: _context(),
            result: text,
            reviews: playerReviews,
            accuracy: accuracy,
          ),
          CoachMessageKind.coach,
          gen,
        ));
      } else {
        _say(CoachMessageKind.coach,
            'Your accuracy was ${accuracy.toStringAsFixed(0)}%. Review the flagged moves in the move list to see what the engine preferred.');
      }
    }
  }

  (String, Side?, String) _describeOutcome(Position pos) {
    if (pos.isCheckmate) {
      final winner = pos.turn.opposite;
      return (
        'Checkmate. ${sideName(winner)} wins${winner == playerSide ? ' — congratulations!' : '.'}',
        winner,
        'Checkmate',
      );
    }
    if (pos.isStalemate) {
      return ('Stalemate: the side to move has no legal moves but is not in check. Draw.', null, 'Stalemate');
    }
    if (pos.isInsufficientMaterial) return ('Draw by insufficient material.', null, 'Insufficient material');
    return ('Draw.', null, 'Draw');
  }

  GameContext _context({Position? position, SearchResult? analysis}) {
    final pos = position ?? this.position;
    return GameContext(
      position: pos,
      sanHistory: sanHistory,
      playerSide: playerSide,
      openingName: openingName,
      analysis: analysis ?? (liveAnalysis?.fen == pos.fen ? liveAnalysis : null),
    );
  }

  String _localConceptHint(SearchResult analysis) {
    final best = analysis.bestMove as NormalMove;
    final target = position.board.pieceAt(best.to);
    final after = position.playUnchecked(best);
    if (after.isCheckmate) return 'There is a checkmate on the board. Look at every check.';
    if (after.isCheck) return 'A forcing check is available. Checks first, then captures, then threats.';
    if (target != null) return 'Something can be captured. Count attackers and defenders on the enemy pieces.';
    final threatened = hangingPieces(position, playerSide);
    if (threatened.isNotEmpty) {
      return 'One of your pieces is in danger. Find it, then decide: move it, defend it, or counter-attack.';
    }
    if (position.fullmoves <= 10) return 'Opening principles: develop a piece toward the centre or get your king safe.';
    return 'Improve your worst-placed piece. Which piece does the least right now?';
  }

  String _localExplanation(MoveReview r) {
    final parts = <String>[];
    final hanging = hangingPieces(r.after, r.before.turn);
    if (hanging.isNotEmpty) parts.add('After that move, ${hanging.first.describe().toLowerCase()}.');
    final missed = hangingPieces(r.before, r.before.turn.opposite);
    if (missed.isNotEmpty) {
      parts.add('You could have won material instead: ${missed.first.describe().toLowerCase()}.');
    }
    if (r.punishingMoves.isNotEmpty) {
      parts.add('Here is how the opponent can punish it: '
          '${friendlyLine(r.after, r.punishingMoves, viewer: playerSide, maxPlies: 4)}');
    }
    if (r.bestMove != null) {
      parts.add('A better idea was: ${friendlyMove(r.before, r.bestMove!, viewer: playerSide).toLowerCase()}.');
    }
    parts.add('Take it back and look for checks, captures and threats before you commit.');
    return parts.join(' ');
  }

  /// The longest prefix of [line] that is legal from [start] (PVs from an
  /// aborted iteration can contain a stale tail).
  List<Move> _legalPrefix(Position start, List<Move> line, int max) {
    final out = <Move>[];
    var p = start;
    for (final m in line) {
      if (out.length >= max || !p.isLegal(m)) break;
      out.add(m);
      p = p.playUnchecked(m);
    }
    return out;
  }

  /// Streams a coach reply into a live message. Returns the final text.
  Future<String?> _stream(Stream<String> source, CoachMessageKind kind, int gen) async {
    final msg = CoachMessage(kind, '', streaming: true);
    messages.add(msg);
    _trimMessages();
    notifyListeners();
    // Coalesce token-by-token updates: repainting the whole screen for every
    // few characters is wasteful on phones.
    Timer? flush;
    void scheduleNotify() {
      flush ??= Timer(const Duration(milliseconds: 80), () {
        flush = null;
        notifyListeners();
      });
    }

    // Speak each sentence as soon as it is complete.
    final speak = _speak && _spokenKinds.contains(kind);
    final sentences = SentenceBuffer();

    try {
      await for (final chunk in source) {
        if (gen != _generation) {
          msg.streaming = false;
          flush?.cancel();
          notifyListeners();
          return null;
        }
        msg.text += chunk;
        if (speak) {
          for (final sentence in sentences.feed(chunk)) {
            unawaited(voice!.say(sentence));
          }
        }
        scheduleNotify();
      }
      msg.streaming = false;
      flush?.cancel();
      if (speak) {
        final rest = sentences.flush();
        if (rest.isNotEmpty) unawaited(voice!.say(rest));
      }
      notifyListeners();
      return msg.text;
    } catch (e) {
      msg.streaming = false;
      flush?.cancel();
      if (msg.text.isEmpty) messages.remove(msg);
      _say(CoachMessageKind.error, e.toString());
      return null;
    }
  }

  void _say(CoachMessageKind kind, String text) {
    messages.add(CoachMessage(kind, text));
    _trimMessages();
    notifyListeners();
    if (_speak && _spokenKinds.contains(kind)) unawaited(voice!.say(text));
  }

  void _trimMessages() {
    while (messages.length > 80) {
      messages.removeAt(0);
    }
  }
}
