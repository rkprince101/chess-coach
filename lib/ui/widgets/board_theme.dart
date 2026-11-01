import 'dart:ui' as ui;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Material 3 board theme derived from the app's seed color.
///
/// Squares, highlights and the white pieces come from the same tonal palettes
/// that `ColorScheme.fromSeed` uses (tonal spot), so the board follows dynamic
/// color and light/dark mode like every other surface in the app. Black
/// pieces stay charcoal. Pieces are flat silhouettes painted in code from
/// [_outlines].
class BoardTheme {
  BoardTheme._(this.colorScheme, this.pieceAssets);

  final ChessboardColorScheme colorScheme;
  final PieceAssets pieceAssets;

  static const _maxCached = 4;
  static final Map<String, BoardTheme> _cache = {};

  static BoardTheme of({required int seed, required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final id = '${seed.toRadixString(16)}-${isDark ? 'd' : 'l'}';
    final cached = _cache.remove(id);
    if (cached != null) return _cache[id] = cached; // re-insert as most recent

    final scheme = SchemeTonalSpot(sourceColorHct: Hct.fromInt(seed), isDark: isDark, contrastLevel: 0);
    final theme = BoardTheme._(_colorScheme(scheme, id), _pieceAssets(scheme, id));
    _cache[id] = theme;
    if (_cache.length > _maxCached) {
      final oldest = _cache.remove(_cache.keys.first)!;
      for (final MapEntry(:key, :value) in oldest.pieceAssets.entries) {
        if (key.side == Side.white) ChessgroundImages.instance.evict(value);
      }
    }
    return theme;
  }

  static ChessboardColorScheme _colorScheme(DynamicScheme s, String id) {
    Color tone(TonalPalette p, int t, [double alpha = 1]) => Color(p.get(t)).withValues(alpha: alpha);

    // Flat pieces have no outline, so the squares sit between the light
    // white pieces (see [_pieceAssets]) and charcoal black in both modes.
    final light = tone(s.secondaryPalette, 76);
    final dark = tone(s.primaryPalette, 50);
    // The background painter never repaints on its own, so key it by palette
    // to force a fresh render object when the seed or brightness changes.
    ChessboardBackground bg({bool coords = false, Side orientation = Side.white}) => SolidColorChessboardBackground(
      key: ValueKey('$id-$coords-$orientation'),
      lightSquare: light,
      darkSquare: dark,
      coordinates: coords,
      orientation: orientation,
    );

    return ChessboardColorScheme(
      lightSquare: light,
      darkSquare: dark,
      background: bg(),
      whiteCoordBackground: bg(coords: true),
      blackCoordBackground: bg(coords: true, orientation: Side.black),
      lastMove: HighlightDetails(solidColor: tone(s.tertiaryPalette, 80, 0.6)),
      selected: HighlightDetails(solidColor: tone(s.tertiaryPalette, 60, 0.7)),
      validMoves: tone(s.neutralPalette, 10, 0.28),
      validPremoves: tone(s.neutralVariantPalette, 40, 0.3),
    );
  }

  /// Resolution pieces are rasterised at; chessground scales them per square.
  static const _pieceSize = 320;

  /// Black never changes, so its images are shared by every theme.
  static const _black = Color(0xFF3C3F42);

  /// Pieces are rasterised once per theme and injected into chessground's
  /// [ChessgroundImages] cache under synthetic asset keys, so the board never
  /// tries to load them from the asset bundle.
  static PieceAssets _pieceAssets(DynamicScheme s, String id) {
    // A light tint of the theme hue: cream for warm seeds, lavender for the
    // default purple, and so on. Lighter than either square.
    final white = Color(TonalPalette.of(s.primaryPalette.hue, 24).get(94));
    final assets = <PieceKind, AssetImage>{};
    for (final kind in PieceKind.values) {
      final isWhite = kind.side == Side.white;
      final asset = AssetImage('flat_pieces/${isWhite ? id : 'black'}/${kind.name}');
      if (!ChessgroundImages.instance.containsKey(asset)) {
        ChessgroundImages.instance.add(asset, _render(kind.role, isWhite ? white : _black));
      }
      assets[kind] = asset;
    }
    return assets;
  }

  static ui.Image _render(Role role, Color color) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pieceSize / 100);
    final path = Path();
    for (final outline in _outlines[role]!) {
      path.addPolygon([for (var i = 0; i + 1 < outline.length; i += 2) Offset(outline[i], outline[i + 1])], true);
    }
    canvas.drawPath(path, Paint()..color = color);
    // A hairline in the same colour softens the traced edges.
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..strokeJoin = StrokeJoin.round,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(_pieceSize, _pieceSize);
    picture.dispose();
    return image;
  }
}

/// Piece silhouettes in a 100×100 box standing on y = 95, as flat x,y pairs.
/// Traced from the reference set with tool/trace_pieces.py.
const Map<Role, List<List<double>>> _outlines = {
  Role.pawn: [
    [
      48.34,
      41.47,
      52.27,
      41.47,
      56.8,
      42.99,
      61.04,
      46.62,
      62.85,
      49.64,
      63.76,
      52.66,
      63.76,
      57.2,
      61.95,
      62.04,
      58.32,
      65.97,
      52.27,
      68.69,
      56.8,
      68.99,
      58.32,
      69.6,
      59.53,
      70.81,
      70.71,
      92.28,
      70.41,
      93.79,
      68.9,
      95.0,
      31.4,
      95.0,
      29.59,
      93.49,
      29.89,
      91.67,
      41.08,
      70.51,
      43.5,
      68.99,
      48.34,
      68.69,
      44.41,
      67.48,
      41.08,
      65.36,
      38.36,
      62.04,
      36.54,
      57.2,
      36.85,
      51.45,
      38.66,
      47.52,
      41.08,
      44.8,
      43.2,
      43.29,
    ],
  ],
  Role.rook: [
    [
      28.53,
      31.49,
      36.69,
      31.49,
      37.6,
      32.4,
      37.6,
      40.57,
      38.21,
      41.47,
      45.16,
      41.17,
      45.16,
      32.4,
      46.07,
      31.49,
      54.23,
      31.49,
      55.44,
      32.4,
      55.75,
      41.47,
      62.7,
      41.17,
      62.7,
      32.7,
      63.31,
      31.8,
      72.08,
      31.49,
      72.98,
      32.4,
      72.98,
      50.85,
      70.56,
      52.97,
      64.52,
      53.27,
      67.24,
      69.6,
      72.08,
      91.37,
      72.08,
      93.49,
      71.47,
      94.4,
      66.33,
      95.0,
      28.83,
      94.7,
      27.62,
      93.49,
      27.62,
      91.07,
      31.86,
      75.04,
      36.09,
      53.27,
      30.04,
      52.97,
      28.83,
      52.36,
      27.32,
      50.24,
      27.32,
      32.7,
    ],
  ],
  Role.knight: [
    [
      50.45,
      26.96,
      52.27,
      27.26,
      65.57,
      40.57,
      72.83,
      48.43,
      74.04,
      50.55,
      74.34,
      92.88,
      72.23,
      95.0,
      27.77,
      95.0,
      26.26,
      93.79,
      26.56,
      91.37,
      42.89,
      69.3,
      49.55,
      59.32,
      48.94,
      58.71,
      44.1,
      58.71,
      38.36,
      59.92,
      31.4,
      62.34,
      29.29,
      62.34,
      27.77,
      61.43,
      24.45,
      55.08,
      24.45,
      53.57,
      24.75,
      52.66,
    ],
  ],
  Role.bishop: [
    [
      47.13,
      26.66,
      47.13,
      53.27,
      48.34,
      55.38,
      50.15,
      55.99,
      52.57,
      54.18,
      52.87,
      26.66,
      58.62,
      32.1,
      63.46,
      38.15,
      66.78,
      43.59,
      68.6,
      47.82,
      69.81,
      53.87,
      69.2,
      59.62,
      68.3,
      62.34,
      65.88,
      66.57,
      61.04,
      71.41,
      71.92,
      92.58,
      71.92,
      93.49,
      70.71,
      95.0,
      29.29,
      95.0,
      28.08,
      93.79,
      28.08,
      92.28,
      38.96,
      71.71,
      34.43,
      66.88,
      31.7,
      62.04,
      30.49,
      57.2,
      30.49,
      52.36,
      31.1,
      49.34,
      33.52,
      43.29,
      37.15,
      37.54,
      40.17,
      33.61,
    ],
  ],
  Role.queen: [
    [
      48.64,
      21.21,
      53.18,
      21.82,
      55.29,
      23.03,
      57.41,
      25.45,
      58.32,
      27.87,
      58.01,
      32.7,
      56.8,
      34.82,
      53.48,
      37.54,
      56.2,
      38.45,
      58.62,
      39.96,
      62.85,
      44.2,
      67.69,
      40.26,
      72.53,
      38.15,
      77.67,
      38.15,
      79.79,
      40.26,
      79.79,
      42.38,
      76.46,
      47.52,
      71.92,
      56.59,
      65.57,
      71.41,
      65.88,
      73.23,
      74.34,
      92.28,
      74.04,
      94.09,
      72.83,
      95.0,
      27.17,
      95.0,
      25.96,
      94.09,
      25.66,
      93.19,
      25.96,
      91.67,
      34.73,
      72.62,
      34.73,
      71.41,
      27.47,
      53.87,
      20.82,
      41.17,
      21.42,
      39.66,
      23.54,
      38.15,
      28.38,
      38.15,
      32.91,
      40.26,
      37.45,
      44.2,
      41.68,
      39.96,
      45.92,
      38.15,
      46.52,
      37.54,
      44.41,
      36.33,
      41.99,
      33.31,
      41.38,
      31.19,
      41.38,
      28.17,
      42.59,
      25.14,
      44.1,
      23.33,
      46.52,
      21.82,
    ],
  ],
  Role.king: [
    [
      46.22,
      7.0,
      54.69,
      7.0,
      55.9,
      8.51,
      55.9,
      15.16,
      62.25,
      15.47,
      63.76,
      16.98,
      63.46,
      25.45,
      62.25,
      26.35,
      55.9,
      26.66,
      55.9,
      35.73,
      58.92,
      36.33,
      71.92,
      36.03,
      73.44,
      36.64,
      75.25,
      39.05,
      75.25,
      41.17,
      64.06,
      69.6,
      64.97,
      72.92,
      72.83,
      91.98,
      72.83,
      93.49,
      71.32,
      95.0,
      28.68,
      95.0,
      27.17,
      93.49,
      27.17,
      91.98,
      36.24,
      69.9,
      26.56,
      44.2,
      25.35,
      39.36,
      26.87,
      36.94,
      28.98,
      36.03,
      44.71,
      35.73,
      44.71,
      26.66,
      38.36,
      26.35,
      37.15,
      25.45,
      36.85,
      17.28,
      38.66,
      15.47,
      44.71,
      15.16,
      44.71,
      8.81,
      45.01,
      7.91,
    ],
  ],
};
