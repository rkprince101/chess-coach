import 'package:flutter/material.dart';

/// Page background behind segmented lists. Segments sit one step brighter
/// than the page in light mode and one step lighter in dark mode, so each
/// row reads as its own container without borders or shadows.
Color pageColor(ColorScheme s) => s.brightness == Brightness.light ? s.surfaceContainer : s.surface;

/// Fill for one segment (row) of a [SegmentedList], and for cards in general.
Color segmentColor(ColorScheme s) => s.brightness == Brightness.light ? s.surfaceBright : s.surfaceContainer;

/// Material 3 Expressive segmented list: every child gets its own container,
/// separated by a small gap. The group's outer corners are large and the inner
/// ones small, so the rows still read as one group.
class SegmentedList extends StatelessWidget {
  const SegmentedList({super.key, required this.children});

  final List<Widget> children;

  static const outer = Radius.circular(20);
  static const inner = Radius.circular(4);
  static const gap = 2.0;

  static BorderRadius radiusAt(int index, int count) => BorderRadius.vertical(
        top: index == 0 ? outer : inner,
        bottom: index == count - 1 ? outer : inner,
      );

  @override
  Widget build(BuildContext context) {
    final color = segmentColor(Theme.of(context).colorScheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: Material(
              color: color,
              shape: RoundedRectangleBorder(borderRadius: radiusAt(i, children.length)),
              clipBehavior: Clip.antiAlias,
              // Tiles' ink should fill the segment, not use the global tile shape.
              child: ListTileTheme.merge(
                shape: RoundedRectangleBorder(borderRadius: radiusAt(i, children.length)),
                child: child,
              ),
            ),
          ),
      ],
    );
  }
}

/// Group header shown above a [SegmentedList].
class SegmentHeader extends StatelessWidget {
  const SegmentHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          if (subtitle != null)
            Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
