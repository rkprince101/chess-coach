import 'package:dartchess/dartchess.dart';

import '../engine/search.dart';
import '../models/move_quality.dart';
import '../services/settings.dart';
import 'claude_client.dart';
import 'demo_builder.dart';
import 'facts.dart';
import 'llm_client.dart';
import 'openai_compat_client.dart';

/// Everything the coach needs to know about the current game, rendered as
/// verified text facts for the model.
class GameContext {
  const GameContext({
    required this.position,
    required this.sanHistory,
    required this.playerSide,
    required this.openingName,
    required this.analysis,
  });

  final Position position;
  final List<String> sanHistory;
  final Side playerSide;
  final String? openingName;

  /// Engine analysis of [position], if available.
  final SearchResult? analysis;

  String get movesText {
    if (sanHistory.isEmpty) return '(no moves yet)';
    final buffer = StringBuffer();
    for (var i = 0; i < sanHistory.length; i++) {
      if (i.isEven) buffer.write('${i ~/ 2 + 1}.');
      buffer.write('${sanHistory[i]} ');
    }
    return buffer.toString().trim();
  }

  String render() {
    final lines = <String>[
      'FEN: ${position.fen}',
      'Side to move: ${sideName(position.turn)}',
      'Student plays: ${sideName(playerSide)}',
      'Moves so far: $movesText',
      if (openingName != null) 'Opening: $openingName',
      'Material: ${describeMaterial(position)}',
    ];
    final a = analysis;
    if (a != null && a.bestMove != null) {
      lines.add('Engine evaluation: ${formatScore(a.score, position.turn)} (positive favours White)');
      lines.add('Engine best move: ${position.makeSan(a.bestMove!).$2}');
      lines.add('Engine best line: ${lineToSan(position, a.pv)}');
      lines.add('Engine best line in plain words: ${friendlyLine(position, a.pv, viewer: playerSide)}');
    }
    final hangingOwn = hangingPieces(position, position.turn);
    final hangingOpp = hangingPieces(position, position.turn.opposite);
    if (hangingOwn.isNotEmpty) {
      lines.add('Pieces of the side to move under attack: ${hangingOwn.map((h) => h.describe()).join('; ')}');
    }
    if (hangingOpp.isNotEmpty) {
      lines.add('Opponent pieces that can be won: ${hangingOpp.map((h) => h.describe()).join('; ')}');
    }
    if (position.isCheck) lines.add('The side to move is in check.');
    return lines.join('\n');
  }
}

/// The verdict on one student move.
class MoveReview {
  const MoveReview({
    required this.before,
    required this.after,
    required this.move,
    required this.san,
    required this.quality,
    required this.bestMove,
    required this.bestSan,
    required this.bestLine,
    required this.evalBefore,
    required this.evalAfter,
    required this.winPercentLoss,
    required this.punishingLine,
    this.bestMoves = const [],
    this.punishingMoves = const [],
  });

  final Position before;
  final Position after;
  final Move move;
  final String san;
  final MoveQuality quality;
  final Move? bestMove;
  final String? bestSan;
  final String bestLine;

  /// Evaluation strings from White's point of view.
  final String evalBefore;
  final String evalAfter;
  final double winPercentLoss;

  /// The engine's reply line that exploits the played move.
  final String punishingLine;

  /// The same lines as moves, so the UI can replay them on the board.
  final List<Move> bestMoves;
  final List<Move> punishingMoves;

  Side get student => before.turn;

  String renderFacts() {
    final lines = <String>[
      'Student played: ${describeMove(before, move)}',
      'In plain words: ${friendlyMove(before, move, viewer: student)}',
      'Verdict: ${quality.label} (lost ${winPercentLoss.toStringAsFixed(1)} winning-percentage points)',
      'Evaluation before the move: $evalBefore, after the move: $evalAfter (positive favours White)',
      if (bestSan != null) 'Engine preferred: $bestSan, line: $bestLine',
      if (bestMoves.isNotEmpty)
        'Engine preferred line in plain words: ${friendlyLine(before, bestMoves, viewer: student)}',
      if (punishingLine.isNotEmpty) 'How the opponent can punish the played move: $punishingLine',
      if (punishingMoves.isNotEmpty)
        'Punishment in plain words: ${friendlyLine(after, punishingMoves, viewer: student)}',
    ];
    final hanging = hangingPieces(after, before.turn);
    if (hanging.isNotEmpty) {
      lines.add('After the move these student pieces are en prise: ${hanging.map((h) => h.describe()).join('; ')}');
    }
    final wasHanging = hangingPieces(before, before.turn.opposite);
    if (wasHanging.isNotEmpty) {
      lines.add('Before the move the student could have won: ${wasHanging.map((h) => h.describe()).join('; ')}');
    }
    return lines.join('\n');
  }
}

/// Builds prompts for every coaching situation and streams Claude's answers.
class CoachService {
  CoachService(this.settings, {LlmClient? clientOverride}) : _override = clientOverride;

  final SettingsController settings;
  final LlmClient? _override;

  LlmClient get _client {
    final override = _override;
    if (override != null) return override;
    final p = settings.provider;
    if (p == CoachProvider.claude) {
      return ClaudeClient(apiKey: settings.apiKey, model: settings.model, effort: settings.effort);
    }
    return OpenAiCompatibleClient(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
      providerName: p.label,
    );
  }

  String _system({bool allowReveal = true}) {
    final level = settings.playerLevel;
    final notation = switch (level) {
      PlayerLevel.beginner =>
        'The student is a complete beginner and cannot read chess notation yet. Never write bare notation such as "Nf3", "g5" or "exd5" on its own. Describe every move in words, naming the piece, where it starts and where it lands, e.g. "your knight jumps from g1 to f3". When you mention a square, anchor it to something visible: "the pawn in front of your king", "the corner near your rook". Use the plain-words versions of the lines you are given. Avoid jargon; if a chess term is unavoidable, explain it in the same sentence. Three or four short sentences is the right length.',
      PlayerLevel.intermediate =>
        'The student knows the rules but is not fluent in notation. Pair notation with the piece name the first time a move appears, e.g. "your knight to f3 (Nf3)", and describe key captures in words.',
      PlayerLevel.advanced =>
        'Standard algebraic notation is fine; the student reads it comfortably.',
    };
    final reveal = allowReveal && settings.revealBestMove
        ? 'When a better move exists, name it and explain why it works.'
        : 'Do not state the engine best move outright unless the student explicitly asks for the answer; instead point them toward the idea, piece, or square to look at so they can find it themselves.';
    return '''
You are a warm, expert chess coach living inside a teaching app. You explain chess the way a great human coach does: name the underlying concept, show it concretely on this board, and leave the student with something they can apply next time.

The student's self-described level: ${level.label} (${level.description}).

You will always receive verified facts computed by a chess engine: the position as FEN, the moves so far, evaluations, the engine's preferred line, and any pieces that are hanging. Ground every concrete claim in those facts. Never invent captures, checks, or moves that are not supported by the facts, and use the exact move notation you are given. If the facts do not say why a move is bad, reason only from general principles and say so.

Style rules: plain prose, no markdown, no headings, no bullet points, no bold text. Default to 3 to 6 sentences; go longer only when the student asks a broad question. Be encouraging and honest, never condescending. The app can replay the engine lines on the board for the student, so you do not need to list long sequences of moves; focus on the idea and the one or two moves that matter.

$notation

$reveal
''';
  }

  /// Explains why a flagged move was weak and what to think about instead.
  Stream<String> explainMistake(MoveReview review, GameContext context) {
    final prompt = '''
The student just played a move that the engine grades as "${review.quality.label}". Explain what went wrong and what principle they should apply, then suggest how to approach the retry. Speak directly to the student ("you").

Game facts before the move:
${context.render()}

Move facts:
${review.renderFacts()}
''';
    return _client.streamText(system: _system(), messages: [_user(prompt)]);
  }

  /// Short praise that also teaches, used sparingly for strong moves.
  Stream<String> praiseMove(MoveReview review, GameContext context) {
    final prompt = '''
The student just played the engine's top choice. In two sentences, tell them what the move achieves (name the concept) so they recognise the pattern next time. Do not mention the engine.

Game facts before the move:
${context.render()}

Move facts:
${review.renderFacts()}
''';
    return _client.streamText(system: _system(), messages: [_user(prompt)], maxTokens: 400);
  }

  /// A conceptual hint that does not reveal the move.
  Stream<String> conceptHint(GameContext context) {
    final prompt = '''
The student is stuck and asked for a hint. Give a one or two sentence hint about the idea to look for (a threat to parry, a piece to activate, a weakness to attack) WITHOUT naming the move or the destination square.

Facts:
${context.render()}
''';
    return _client.streamText(
        system: _system(allowReveal: false), messages: [_user(prompt)], maxTokens: 300);
  }

  /// Free-form question about the current position, with chat history.
  Stream<String> ask(String question, GameContext context, List<Map<String, dynamic>> history) {
    final prompt = '''
Current game facts (refreshed for this question):
${context.render()}

Student's question: $question
''';
    return _client.streamText(
      system: _system(),
      messages: [...history, _user(prompt)],
      maxTokens: 3000,
    );
  }

  /// End-of-game review.
  Stream<String> gameSummary({
    required GameContext context,
    required String result,
    required List<MoveReview> reviews,
    required double accuracy,
  }) {
    final worst = [...reviews.where((r) => r.quality.isBad)]
      ..sort((a, b) => b.winPercentLoss.compareTo(a.winPercentLoss));
    final worstText = worst.take(4).map((r) {
      final moveNo = (r.before.fullmoves).toString() + (r.before.turn == Side.white ? '.' : '...');
      return '$moveNo${r.san} (${r.quality.label}; better was ${r.bestSan ?? '?'}; ${r.evalBefore} to ${r.evalAfter})';
    }).join('\n');
    final counts = <MoveQuality, int>{};
    for (final r in reviews) {
      counts.update(r.quality, (v) => v + 1, ifAbsent: () => 1);
    }
    final countText = MoveQuality.values
        .where((q) => counts.containsKey(q))
        .map((q) => '${q.label}: ${counts[q]}')
        .join(', ');
    final prompt = '''
The game is over. Result: $result. Write a short post-game review for the student in 2 or 3 short paragraphs: what they did well, the two or three most important lessons from their worst moves (reference the move numbers), and one concrete thing to practise next. Plain prose only.

Student accuracy: ${accuracy.toStringAsFixed(0)}%. Move quality counts: $countText.
Moves: ${context.movesText}
${context.openingName != null ? 'Opening: ${context.openingName}' : ''}

Worst moves with engine facts:
$worstText
''';
    return _client.streamText(system: _system(), messages: [_user(prompt)], maxTokens: 2500);
  }

  /// Teaches any chess topic (concept library / lesson deep dive).
  Stream<String> teachTopic(String topic, {String? positionFen, String? lessonText}) {
    final prompt = '''
Teach the student about: $topic.
${lessonText != null ? 'The lesson currently on screen says: "$lessonText"\n' : ''}${positionFen != null ? 'Position on the board (FEN): $positionFen\n' : ''}
Structure it as a short spoken explanation in 2 to 4 short paragraphs: what the idea is, why it matters, how to recognise it during a game, and one memorable rule of thumb. Plain prose, no lists. If the topic is a specific opening, give the first few moves in SAN and the plans for both sides.
''';
    return _client.streamText(system: _system(), messages: [_user(prompt)], maxTokens: 3000);
  }

  /// Asks the model for a structured on-board demonstration of [topic],
  /// validates every position and move, and retries once with the list of
  /// problems if nothing legal came back. Returns null when even the retry
  /// produced nothing usable.
  Future<BoardDemo?> buildDemo(String topic, {void Function(String status)? onStatus}) async {
    onStatus?.call('Asking the coach to set up the board…');
    final first = await _client
        .streamText(system: _system(), messages: [_user(demoPrompt(topic))], maxTokens: 6000)
        .join();
    var demo = parseDemo(first);
    if (demo != null && demo.steps.isNotEmpty) return demo;

    onStatus?.call('Fixing illegal positions, one more try…');
    final problems = demo == null
        ? 'The reply was not valid JSON in the requested shape.'
        : demo.problems.isEmpty
            ? 'No steps were returned.'
            : demo.problems.join(' | ');
    final second = await _client
        .streamText(
          system: _system(),
          messages: [_user(demoPrompt(topic, previousProblems: problems))],
          maxTokens: 6000,
        )
        .join();
    final retry = parseDemo(second);
    if (retry != null && retry.steps.isNotEmpty) return retry;
    return retry ?? demo;
  }

  /// Continues a concept-library conversation.
  Stream<String> followUp(String question, List<Map<String, dynamic>> history) {
    return _client.streamText(
      system: _system(),
      messages: [...history, _user(question)],
      maxTokens: 3000,
    );
  }

  Map<String, dynamic> _user(String text) => {'role': 'user', 'content': text};
}
