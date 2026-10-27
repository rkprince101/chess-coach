import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../../models/move_quality.dart';

/// Vertical evaluation bar: the white part grows as White's winning chances
/// increase. [cpWhite] is centipawns from White's point of view.
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.cpWhite,
    required this.height,
    required this.orientation,
    this.label,
  }) : axis = Axis.vertical;

  /// Thin horizontal bar for stacked phone layouts; White's share grows from
  /// the side the player sits on.
  const EvalBar.horizontal({
    super.key,
    required this.cpWhite,
    required double width,
    required this.orientation,
    this.label,
  })  : height = width,
        axis = Axis.horizontal;

  final int? cpWhite;
  final double height;
  final Side orientation;
  final String? label;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final fraction = cpWhite == null ? 0.5 : winPercent(cpWhite!) / 100;
    if (axis == Axis.horizontal) return _horizontal(context, fraction);
    final whiteOnBottom = orientation == Side.white;
    return SizedBox(
      width: 22,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(color: const Color(0xFF3A3A3A)),
            AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              alignment: whiteOnBottom ? Alignment.bottomCenter : Alignment.topCenter,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                heightFactor: fraction.clamp(0.02, 0.98),
                widthFactor: 1,
                child: Container(color: const Color(0xFFF2F2F2)),
              ),
            ),
            if (label != null)
              Align(
                alignment: (fraction >= 0.5) == whiteOnBottom
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      label!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: fraction >= 0.5 ? Colors.black87 : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _horizontal(BuildContext context, double fraction) {
    final whiteOnLeft = orientation == Side.white;
    return SizedBox(
      width: height,
      height: 14,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(color: const Color(0xFF3A3A3A)),
            AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              alignment: whiteOnLeft ? Alignment.centerLeft : Alignment.centerRight,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                widthFactor: fraction.clamp(0.02, 0.98),
                heightFactor: 1,
                child: Container(color: const Color(0xFFF2F2F2)),
              ),
            ),
            if (label != null)
              Center(
                child: Text(
                  label!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: fraction >= 0.5 ? Colors.black87 : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
