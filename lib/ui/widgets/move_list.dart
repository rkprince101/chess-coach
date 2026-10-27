import 'package:flutter/material.dart';

import '../../state/game_controller.dart';

/// Compact move list with a quality dot on each graded move. Tapping a move
/// shows that position on the board; the "Live" chip returns to the game.
class MoveList extends StatelessWidget {
  const MoveList({
    super.key,
    required this.history,
    required this.viewIndex,
    required this.onSelect,
  });

  final List<HistoryEntry> history;
  final int? viewIndex;
  final void Function(int? index) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (history.isEmpty) {
      return Text('No moves yet.', style: TextStyle(color: scheme.outline));
    }
    final chips = <Widget>[];
    for (var i = 0; i < history.length; i++) {
      final h = history[i];
      final selected = viewIndex == i;
      final quality = h.review?.quality;
      final prefix = i.isEven ? '${i ~/ 2 + 1}. ' : '';
      chips.add(
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onSelect(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$prefix${h.san}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    )),
                if (quality != null) ...[
                  const SizedBox(width: 3),
                  Tooltip(
                    message: quality.label,
                    child: Icon(quality.icon, size: 13, color: quality.color),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...chips,
        if (viewIndex != null)
          ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Live'),
            onPressed: () => onSelect(null),
          ),
      ],
    );
  }
}

/// Single-line, horizontally scrolling move list for phones. Keeps the most
/// recent move in view.
class MoveStrip extends StatefulWidget {
  const MoveStrip({
    super.key,
    required this.history,
    required this.viewIndex,
    required this.onSelect,
  });

  final List<HistoryEntry> history;
  final int? viewIndex;
  final void Function(int? index) onSelect;

  @override
  State<MoveStrip> createState() => _MoveStripState();
}

class _MoveStripState extends State<MoveStrip> {
  final _scroll = ScrollController();
  int _lastLength = 0;

  @override
  void didUpdateWidget(covariant MoveStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.history.length != _lastLength && widget.viewIndex == null) {
      _lastLength = widget.history.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.history.isEmpty) {
      return SizedBox(
        height: 30,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No moves yet.', style: TextStyle(color: scheme.outline, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: 30,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: widget.history.length + (widget.viewIndex != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == widget.history.length) {
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                label: const Text('Live', style: TextStyle(fontSize: 12)),
                onPressed: () => widget.onSelect(null),
              ),
            );
          }
          final h = widget.history[i];
          final selected = widget.viewIndex == i;
          final quality = h.review?.quality;
          final prefix = i.isEven ? '${i ~/ 2 + 1}.' : '';
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => widget.onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$prefix${h.san}',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      )),
                  if (quality != null) ...[
                    const SizedBox(width: 2),
                    Icon(quality.icon, size: 12, color: quality.color),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
