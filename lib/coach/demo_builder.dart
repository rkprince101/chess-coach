import 'dart:convert';

import 'package:chessground/chessground.dart' show Arrow, Circle, Shape;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart' show Color;

import '../data/lessons_data.dart';
import '../models/lesson.dart';

/// One board scene of an AI-built concept demo: a verified start position,
/// optional moves to play through, and plain-English captions.
class DemoStep {
  DemoStep({
    required this.title,
    required this.text,
    required this.start,
    required this.moves,
    required this.shapes,
    this.afterText,
    this.truncated = false,
  });

  final String title;
  final String text;
  final Position start;
  final List<Move> moves;
  final Set<Shape> shapes;
  final String? afterText;

  /// True when some of the model's moves were illegal and dropped.
  final bool truncated;

  late final List<Position> positions = () {
    final list = [start];
    var p = start;
    for (final m in moves) {
      p = p.playUnchecked(m);
      list.add(p);
    }
    return list;
  }();
}

class BoardDemo {
  const BoardDemo({
    required this.title,
    required this.intro,
    required this.steps,
    required this.summary,
    required this.problems,
  });

  final String title;
  final String intro;
  final List<DemoStep> steps;
  final String summary;

  /// Human-readable notes about what had to be dropped during validation.
  final List<String> problems;
}

/// Builds the instructions the model gets for a board demo, including any
/// verified positions from the built-in lessons that match the topic.
String demoPrompt(String topic, {String? previousProblems}) {
  final examples = _matchingLessonSteps(topic);
  final exampleText = examples.isEmpty
      ? ''
      : '''
Verified positions you may reuse (they are guaranteed legal; prefer them over inventing your own):
${examples.map((e) => '- ${e.title}: FEN "${e.fen}"${e.line.isNotEmpty ? ', moves ${e.line.join(' ')}' : ''}').join('\n')}
''';
  final retry = previousProblems == null
      ? ''
      : '''
Your previous attempt had these problems, fix them and return the whole JSON again:
$previousProblems
''';
  return '''
Build a short on-board demonstration that teaches: "$topic".

Return ONLY a JSON object, no markdown fences, no prose outside the JSON, with this exact shape:
{
  "title": "short title",
  "intro": "2 or 3 plain sentences: what the idea is and why it matters",
  "steps": [
    {
      "title": "short step title",
      "fen": "a complete, legal FEN string",
      "text": "what the student should look at in this position, before any move is played",
      "moves": ["SAN", "SAN"],
      "arrows": ["e2e4"],
      "highlights": ["e4"],
      "after": "one or two sentences about what the moves achieved"
    }
  ],
  "summary": "one memorable rule of thumb"
}

Rules for the positions:
- 2 to 4 steps. Use simple positions with few pieces so the idea is obvious. Both kings must be on the board, the side to move must not already be giving check, and no pawns on the first or eighth rank.
- The side to move in the FEN must be the side that plays the first move in "moves". Every move must be legal in standard algebraic notation (e.g. Nf3, exd5, O-O, e8=Q, Qxf7#). 0 to 6 moves per step. Check each move square by square before you answer.
- "arrows" are from-square+to-square pairs (e.g. "g1f3") drawn on the starting position to point at the idea; "highlights" are single squares. Use them generously so the student sees where to look.
- Text fields follow your usual coaching style for this student's level (describe moves in words there; the "moves" array is the only place notation belongs).
$exampleText$retry''';
}

/// Built-in lessons whose title or summary shares a meaningful word with
/// [topic]; used both to seed the model and to offer hands-on practice.
List<Lesson> matchingLessons(String topic) {
  final words = topic
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(' ')
      .where((w) => w.length > 3 && !_stopWords.contains(w))
      .toSet();
  if (words.isEmpty) return const [];
  final scored = <(Lesson, int)>[];
  for (final lesson in lessons) {
    final title = lesson.title.toLowerCase();
    final rest = '${lesson.summary} ${lesson.id}'.toLowerCase();
    var score = 0;
    if (title.contains(topic.toLowerCase().trim())) score += 10;
    for (final w in words) {
      if (title.contains(w)) score += 3;
      if (rest.contains(w)) score += 1;
    }
    if (score > 0) scored.add((lesson, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).toList();
}

List<LessonStep> _matchingLessonSteps(String topic) => [
      for (final lesson in matchingLessons(topic).take(3))
        for (final step in lesson.steps)
          if (step.goal != GoalType.read) step,
    ].take(6).toList();

const _stopWords = {'with', 'from', 'that', 'this', 'what', 'when', 'your', 'chess', 'attack', 'defense', 'defence', 'game', 'opening'};

/// Parses and validates the model's JSON. Never throws: bad steps are dropped
/// and reported in [BoardDemo.problems]; returns null only if nothing usable
/// came back at all.
BoardDemo? parseDemo(String raw) {
  final json = _extractJson(raw);
  if (json == null) return null;

  final problems = <String>[];
  final steps = <DemoStep>[];
  final rawSteps = json['steps'];
  if (rawSteps is List) {
    for (final (i, item) in rawSteps.indexed) {
      if (item is! Map) continue;
      final label = (item['title'] as String?)?.trim();
      final stepName = label == null || label.isEmpty ? 'Step ${i + 1}' : label;
      final fen = (item['fen'] as String?)?.trim();
      if (fen == null || fen.isEmpty) {
        problems.add('$stepName: missing FEN.');
        continue;
      }
      final Position start;
      try {
        start = Chess.fromSetup(Setup.parseFen(fen));
      } catch (e) {
        problems.add('$stepName: FEN "$fen" is not a legal position ($e).');
        continue;
      }
      if (start.isCheckmate || start.isStalemate) {
        problems.add('$stepName: the position is already over.');
        continue;
      }

      final moves = <Move>[];
      var truncated = false;
      var p = start;
      final rawMoves = item['moves'];
      if (rawMoves is List) {
        for (final mv in rawMoves.take(8)) {
          if (mv is! String) continue;
          final parsed = p.parseSan(mv.trim()) ?? _parseUci(p, mv.trim());
          if (parsed == null) {
            problems.add('$stepName: move "$mv" is illegal in ${p.fen}; later moves were dropped.');
            truncated = true;
            break;
          }
          moves.add(parsed);
          p = p.playUnchecked(parsed);
        }
      }

      final shapes = <Shape>{};
      final arrows = item['arrows'];
      if (arrows is List) {
        for (final a in arrows) {
          if (a is! String) continue;
          final clean = a.replaceAll(RegExp(r'[^a-h1-8]'), '');
          if (clean.length != 4) continue;
          final from = Square.parse(clean.substring(0, 2));
          final to = Square.parse(clean.substring(2, 4));
          if (from != null && to != null && from != to) {
            shapes.add(Arrow(color: const Color(0xAA2196F3), orig: from, dest: to));
          }
        }
      }
      final highlights = item['highlights'];
      if (highlights is List) {
        for (final h in highlights) {
          if (h is! String) continue;
          final sq = Square.parse(h.trim().toLowerCase());
          if (sq != null) shapes.add(Circle(color: const Color(0x99FFC107), orig: sq));
        }
      }

      steps.add(DemoStep(
        title: stepName,
        text: (item['text'] as String?)?.trim() ?? '',
        start: start,
        moves: moves,
        shapes: shapes,
        afterText: (item['after'] as String?)?.trim(),
        truncated: truncated,
      ));
    }
  }

  final title = (json['title'] as String?)?.trim() ?? '';
  final intro = (json['intro'] as String?)?.trim() ?? '';
  final summary = (json['summary'] as String?)?.trim() ?? '';
  if (steps.isEmpty && intro.isEmpty) return null;
  return BoardDemo(title: title, intro: intro, steps: steps, summary: summary, problems: problems);
}

Move? _parseUci(Position p, String text) {
  final m = Move.parse(text);
  if (m == null) return null;
  final normalized = m is NormalMove ? p.normalizeMove(m) : m;
  return p.isLegal(normalized) ? normalized : null;
}

Map<String, dynamic>? _extractJson(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true).firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
