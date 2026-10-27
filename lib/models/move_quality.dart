import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/search.dart';

enum MoveQuality {
  best('Best', Color(0xFF2E7D32), Icons.star_rounded),
  good('Good', Color(0xFF4CAF50), Icons.check_circle_rounded),
  book('Book', Color(0xFF8D6E63), Icons.menu_book_rounded),
  inaccuracy('Inaccuracy', Color(0xFFF9A825), Icons.error_outline_rounded),
  mistake('Mistake', Color(0xFFEF6C00), Icons.warning_amber_rounded),
  blunder('Blunder', Color(0xFFC62828), Icons.dangerous_rounded);

  const MoveQuality(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;

  /// Whether the coach should interrupt play and offer a retry.
  bool get needsCoaching =>
      this == MoveQuality.inaccuracy || this == MoveQuality.mistake || this == MoveQuality.blunder;

  bool get isBad => needsCoaching;
}

/// Converts a centipawn score into an expected winning percentage (0-100)
/// using the same logistic curve lichess uses for its accuracy metric. This
/// makes a 200cp swing matter a lot at 0.00 and very little at +9.00.
double winPercent(int cp) {
  final clamped = cp.clamp(-2000, 2000);
  return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * clamped)) - 1);
}

/// Normalises mate scores into a large centipawn value for comparisons.
int scoreToCp(int score) {
  if (!isMateScore(score)) return score;
  final m = mateIn(score);
  return m > 0 ? 3000 - m * 10 : -3000 - m * 10;
}

/// Classifies a move by comparing the best available evaluation with the
/// evaluation of the position after the played move, both from the mover's
/// point of view.
MoveQuality classifyMove({
  required int bestScore,
  required int playedScore,
  required bool playedIsBest,
}) {
  if (playedIsBest) return MoveQuality.best;

  final bestCp = scoreToCp(bestScore);
  final playedCp = scoreToCp(playedScore);

  // Losing a forced mate, or walking into one, is always a blunder.
  if (isMateScore(bestScore) && bestScore > 0 && !(isMateScore(playedScore) && playedScore > 0)) {
    return MoveQuality.blunder;
  }
  if (isMateScore(playedScore) && playedScore < 0 && !(isMateScore(bestScore) && bestScore < 0)) {
    return MoveQuality.blunder;
  }

  final loss = winPercent(bestCp) - winPercent(playedCp);
  if (loss < 2) return MoveQuality.best;
  if (loss < 6) return MoveQuality.good;
  if (loss < 12) return MoveQuality.inaccuracy;
  if (loss < 22) return MoveQuality.mistake;
  return MoveQuality.blunder;
}

/// Accuracy percentage for a list of per-move win% losses (lichess formula).
double accuracyFromLosses(Iterable<double> losses) {
  if (losses.isEmpty) return 100;
  var total = 0.0;
  var n = 0;
  for (final loss in losses) {
    final acc = 103.1668 * math.exp(-0.04354 * loss) - 3.1669;
    total += acc.clamp(0, 100);
    n++;
  }
  return total / n;
}
