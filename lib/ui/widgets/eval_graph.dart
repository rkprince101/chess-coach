import 'package:flutter/material.dart';

import '../../models/move_quality.dart';

/// Win-probability curve of a whole game from White's point of view: White's
/// share fills from the bottom. Graded mistakes are dotted in their colour
/// and the selected position is marked. Tap or drag to pick a position.
class EvalGraph extends StatelessWidget {
  const EvalGraph({
    super.key,
    required this.evalCp,
    required this.qualities,
    required this.selected,
    required this.onSelect,
    this.height = 96,
  });

  /// One evaluation per position, White's point of view, in centipawns.
  final List<int> evalCp;

  /// Grade of each move (one fewer than [evalCp]).
  final List<MoveQuality?> qualities;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(double dx) {
          if (evalCp.length < 2) return;
          final i = (dx / width * (evalCp.length - 1)).round().clamp(0, evalCp.length - 1);
          if (i != selected) onSelect(i);
        }

        return Semantics(
          label: 'Evaluation graph',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => pick(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                size: Size(width, height),
                painter: _EvalGraphPainter(
                  evalCp: evalCp,
                  qualities: qualities,
                  selected: selected,
                  white: const Color(0xFFF2F2F2),
                  black: const Color(0xFF3A3A3A),
                  midline: scheme.outline.withValues(alpha: 0.5),
                  marker: scheme.primary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EvalGraphPainter extends CustomPainter {
  _EvalGraphPainter({
    required this.evalCp,
    required this.qualities,
    required this.selected,
    required this.white,
    required this.black,
    required this.midline,
    required this.marker,
  });

  final List<int> evalCp;
  final List<MoveQuality?> qualities;
  final int selected;
  final Color white;
  final Color black;
  final Color midline;
  final Color marker;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = black);
    if (evalCp.isEmpty) return;
    final n = evalCp.length;
    double x(int i) => n == 1 ? size.width / 2 : i / (n - 1) * size.width;
    // Keep a sliver of each colour visible even when one side is winning.
    double y(int i) => size.height * (1 - (winPercent(evalCp[i]) / 100).clamp(0.03, 0.97));

    final area = Path()..moveTo(0, size.height);
    for (var i = 0; i < n; i++) {
      area.lineTo(x(i), y(i));
    }
    area
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = white);

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = midline
        ..strokeWidth = 1,
    );

    final sel = selected.clamp(0, n - 1);
    canvas.drawLine(
      Offset(x(sel), 0),
      Offset(x(sel), size.height),
      Paint()
        ..color = marker
        ..strokeWidth = 2,
    );

    for (var i = 0; i < qualities.length && i + 1 < n; i++) {
      final q = qualities[i];
      if (q == null || !(q.isBad || q == MoveQuality.brilliant || q == MoveQuality.great)) continue;
      final c = Offset(x(i + 1), y(i + 1));
      canvas.drawCircle(c, 4.5, Paint()..color = white);
      canvas.drawCircle(c, 3.5, Paint()..color = q.color);
    }
    canvas.drawCircle(Offset(x(sel), y(sel)), 4, Paint()..color = marker);
  }

  @override
  bool shouldRepaint(covariant _EvalGraphPainter old) =>
      old.evalCp != evalCp ||
      old.qualities != qualities ||
      old.selected != selected ||
      old.midline != midline ||
      old.marker != marker;
}
