import 'package:flutter/material.dart';

// M3 motion: enter on emphasized decelerate, exit on emphasized accelerate.
const _enterCurve = Cubic(0.05, 0.7, 0.1, 1);
const _exitCurve = Cubic(0.3, 0, 0.8, 0.15);

/// Shows a dialog that scales and fades in with Material 3 emphasized motion.
/// Dismissing via the barrier pops with null.
Future<T?> showExpressiveDialog<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: _enterCurve, reverseCurve: _exitCurve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// Dialog shell: a hero icon on an expressive scalloped badge, a centred
/// headline and message, optional scrollable content, and full-width stacked
/// actions (see [ExpressiveDialog.primary] and friends).
class ExpressiveDialog extends StatelessWidget {
  const ExpressiveDialog({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.badgeColor,
    required this.title,
    this.message,
    this.content,
    required this.actions,
  });

  final IconData icon;
  final Color iconColor;
  final Color badgeColor;
  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;

  /// Large (52dp) full-width pill with the theme's label font, bumped up.
  static ButtonStyle _actionStyle(BuildContext context) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        iconSize: const WidgetStatePropertyAll(20),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );

  /// Elevated buttons share the tile fill so they lift off the dialog surface.
  static ButtonStyle _elevatedStyle(BuildContext context) => _actionStyle(context).copyWith(
        backgroundColor: WidgetStatePropertyAll(dialogTileColor(Theme.of(context).colorScheme)),
      );

  /// The one high-emphasis action.
  static Widget primary({required IconData icon, required String label, required VoidCallback onPressed}) =>
      Builder(
        builder: (context) => FilledButton.icon(
          style: _actionStyle(context),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );

  /// Medium-emphasis elevated action.
  static Widget secondary({required IconData icon, required String label, required VoidCallback onPressed}) =>
      Builder(
        builder: (context) => ElevatedButton.icon(
          style: _elevatedStyle(context),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );

  /// Elevated action in the error color, for throwing something away.
  static Widget destructive({required IconData icon, required String label, required VoidCallback onPressed}) =>
      Builder(
        builder: (context) {
          final error = Theme.of(context).colorScheme.error;
          return ElevatedButton.icon(
            style: _elevatedStyle(context).copyWith(
              foregroundColor: WidgetStatePropertyAll(error),
              iconColor: WidgetStatePropertyAll(error),
            ),
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _Badge(icon: icon, iconColor: iconColor, color: badgeColor)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: 20),
                Flexible(child: SingleChildScrollView(child: content)),
              ],
              const SizedBox(height: 24),
              for (final (i, action) in actions.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Scalloped "cookie" badge that springs in.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.iconColor, required this.color});

  final IconData icon;
  final Color iconColor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.rotate(
        angle: (1 - t) * -0.6,
        child: Transform.scale(scale: t, child: child),
      ),
      child: Container(
        width: 84,
        height: 84,
        decoration: ShapeDecoration(
          color: color,
          shape: StarBorder(points: 9, innerRadiusRatio: 0.84, pointRounding: 0.5, valleyRounding: 0.5),
        ),
        child: Icon(icon, size: 40, color: iconColor),
      ),
    );
  }
}

/// Fill for tiles inside a dialog: separates from the dialog surface in
/// both light and dark mode.
Color dialogTileColor(ColorScheme s) =>
    s.brightness == Brightness.light ? s.surfaceContainerLowest : s.surfaceContainerHighest;

/// Grid of tiles with segmented-list corners: large on the outside of the
/// group, small between tiles.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.rows});

  final List<List<Widget>> rows;

  static const _outer = Radius.circular(20);
  static const _inner = Radius.circular(4);
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final color = dialogTileColor(Theme.of(context).colorScheme);
    final last = rows.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const SizedBox(height: _gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (c, tile) in row.indexed) ...[
                  if (c > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.only(
                          topLeft: r == 0 && c == 0 ? _outer : _inner,
                          topRight: r == 0 && c == row.length - 1 ? _outer : _inner,
                          bottomLeft: r == last && c == 0 ? _outer : _inner,
                          bottomRight: r == last && c == row.length - 1 ? _outer : _inner,
                        ),
                      ),
                      child: tile,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Icon + big value + label, for a [TileGrid].
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label, this.valueColor});

  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: valueColor),
          ),
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
        ],
      ),
    );
  }
}
