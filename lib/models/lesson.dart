import 'package:dartchess/dartchess.dart';

enum GoalType {
  /// Nothing to do on the board; the student reads and continues.
  read,

  /// Play the given SAN line; opponent replies in the line are auto-played.
  playLine,

  /// Move a piece to [LessonStep.targetSquare] within [LessonStep.maxMoves]
  /// moves. The opponent never moves.
  reachSquare,

  /// Capture every enemy piece except the king. The opponent never moves.
  captureAll,

  /// Deliver checkmate within [LessonStep.maxMoves] against the engine.
  checkmate,

  /// Promote a pawn within [LessonStep.maxMoves] against the engine.
  promote,

  /// Any legal move completes the step (used to practise escaping check).
  anyMove,
}

class LessonStep {
  const LessonStep({
    required this.title,
    required this.text,
    required this.fen,
    this.goal = GoalType.read,
    this.line = const [],
    this.notes = const [],
    this.targetSquare,
    this.maxMoves,
    this.successText,
    this.highlights = const [],
    this.arrows = const [],
  });

  final String title;
  final String text;
  final String fen;
  final GoalType goal;

  /// SAN moves for [GoalType.playLine], student and opponent alternating,
  /// starting with the side to move in [fen].
  final List<String> line;

  /// Optional teaching note shown after each ply of [line] is played.
  final List<String?> notes;
  final Square? targetSquare;
  final int? maxMoves;
  final String? successText;
  final List<Square> highlights;
  final List<(Square, Square)> arrows;

  Side get studentSide => Setup.parseFen(fen).turn;
}

enum LessonCategory {
  basics('Basics', 'How every piece moves'),
  specialMoves('Special Moves', 'Castling, en passant, promotion'),
  fundamentals('Fundamentals', 'Check, mate, values, principles'),
  tactics('Tactics', 'Forks, pins, skewers and more'),
  checkmates('Checkmates & Endgames', 'Finish the game'),
  openings('Openings', 'Guided tours of the main openings');

  const LessonCategory(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.category,
    required this.summary,
    required this.steps,
  });

  final String id;
  final String title;
  final LessonCategory category;
  final String summary;
  final List<LessonStep> steps;
}
