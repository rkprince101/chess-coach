import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Side-by-side board and panel when there is room (desktop, tablets,
/// landscape phones); board above panel otherwise.
bool isWideLayout(BoxConstraints c) =>
    c.maxWidth >= 860 || (c.maxWidth > c.maxHeight && c.maxWidth >= 640);

/// Board edge for the stacked (portrait) layout: full width, but never more
/// than [heightFraction] of the available height so the panel keeps room.
double stackedBoardSize(BoxConstraints c, {double heightFraction = 0.5, double sidePadding = 16}) =>
    math.max(120, math.min(c.maxWidth - sidePadding, c.maxHeight * heightFraction));

/// Board edge for the side-by-side layout.
double sideBySideBoardSize(BoxConstraints c, {double widthFraction = 0.55, double reserve = 60}) =>
    math.max(200, math.min(c.maxHeight - 32, c.maxWidth * widthFraction - reserve));

/// Phone-sized screens get denser controls.
bool isCompactWidth(BoxConstraints c) => c.maxWidth < 600;

/// [base] plus the system insets (navigation bar, display cutouts), so
/// edge-to-edge scroll content draws under the bars but scrolls clear of them.
/// Use where an explicit `padding` would otherwise drop ListView's own insets.
EdgeInsets withSystemInsets(BuildContext context, EdgeInsets base) =>
    base + MediaQuery.paddingOf(context);
