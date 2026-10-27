import 'dart:ui' as ui;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Material 3 board theme derived from the app's seed color.
///
/// Squares and highlights come from the same tonal palettes that
/// `ColorScheme.fromSeed` uses (tonal spot), so the board follows dynamic
/// color and light/dark mode like every other surface in the app. Pieces are
/// a fixed faceted set painted in code (see [_FacetPainter]).
class BoardTheme {
  BoardTheme._(this.colorScheme);

  final ChessboardColorScheme colorScheme;

  /// Pieces are rasterised once, on first use, and injected into chessground's
  /// [ChessgroundImages] cache under synthetic asset keys, so the board never
  /// tries to load them from the asset bundle.
  static final PieceAssets pieceAssets = _renderPieces();

  static final Map<String, BoardTheme> _cache = {};

  static BoardTheme of({required int seed, required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final id = '${seed.toRadixString(16)}-${isDark ? 'd' : 'l'}';
    return _cache[id] ??= BoardTheme._(_colorScheme(
      SchemeTonalSpot(sourceColorHct: Hct.fromInt(seed), isDark: isDark, contrastLevel: 0),
      isDark,
      id,
    ));
  }

  static ChessboardColorScheme _colorScheme(DynamicScheme s, bool isDark, String id) {
    Color tone(TonalPalette p, int t, [double alpha = 1]) =>
        Color(p.get(t)).withValues(alpha: alpha);

    final light = tone(s.secondaryPalette, isDark ? 80 : 90);
    final dark = tone(s.primaryPalette, isDark ? 50 : 60);
    // The background painter never repaints on its own, so key it by palette
    // to force a fresh render object when the seed or brightness changes.
    ChessboardBackground bg({bool coords = false, Side orientation = Side.white}) =>
        SolidColorChessboardBackground(
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

  static PieceAssets _renderPieces() {
    final assets = <PieceKind, AssetImage>{};
    for (final kind in PieceKind.values) {
      final asset = AssetImage('faceted_pieces/${kind.name}');
      if (!ChessgroundImages.instance.containsKey(asset)) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(_pieceSize / 100);
        _FacetPainter(canvas, kind.side == Side.white ? _ivory : _onyx).paint(kind.role);
        final picture = recorder.endRecording();
        ChessgroundImages.instance.add(asset, picture.toImageSync(_pieceSize, _pieceSize));
        picture.dispose();
      }
      assets[kind] = asset;
    }
    return assets;
  }
}

/// Lit (left) and shaded (right) face tones for one side's pieces.
class _Palette {
  const _Palette(this.left, this.right);

  final _Tones left;
  final _Tones right;
}

/// A face's base tone plus its tone when tilted fully up or fully down.
class _Tones {
  const _Tones(this.base, this.up, this.down);

  final Color base;
  final Color up;
  final Color down;

  Color at(double tilt) =>
      tilt >= 0 ? Color.lerp(base, up, tilt)! : Color.lerp(base, down, -tilt)!;
}

const _ivory = _Palette(
  _Tones(Color(0xFFE9D6BA), Color(0xFFF2E3CD), Color(0xFFDDC3A0)),
  _Tones(Color(0xFFD0B388), Color(0xFFDCC29C), Color(0xFFC6A87D)),
);

const _onyx = _Palette(
  _Tones(Color(0xFF34353A), Color(0xFF3D3E44), Color(0xFF2D2E32)),
  _Tones(Color(0xFF1F2023), Color(0xFF28292D), Color(0xFF1A1B1E)),
);

/// Paints one low-poly piece in a 100×100 box, standing on y = 96.
///
/// Symmetric pieces are described by a profile: (y, half-width) pairs from
/// top to bottom. Each band between two profile points becomes a facet on
/// both halves; its tilt (how much it widens going down, i.e. faces up
/// toward the light) picks the tone. The left half takes the lit palette and
/// the right half the shaded one, giving the centre ridge.
class _FacetPainter {
  _FacetPainter(this.canvas, this.palette);

  final Canvas canvas;
  final _Palette palette;

  /// Per-piece scale about the base, compressing true Staunton heights so
  /// pawns stay readable on a square.
  static const _scale = {
    Role.pawn: 1.25,
    Role.rook: 1.18,
    Role.knight: 1.12,
    Role.bishop: 1.07,
    Role.queen: 1.05,
    Role.king: 1.0,
  };

  void paint(Role role) {
    final k = _scale[role]!;
    canvas
      ..save()
      ..translate(50, 96)
      ..scale(k)
      ..translate(-50, -96);
    switch (role) {
      case Role.pawn:
        _profile(const [(48, 0), (51.5, 7.4), (57.5, 10), (63.5, 8.4), (66.5, 4.6)]);
        _profile(const [(66.3, 5.4), (69, 6.8), (84, 12.2), (89, 16.6), (96, 16.6)]);
      case Role.rook:
        // Battlement block: three merlons, two notches.
        _facet(const [(0, 39), (3.7, 39), (3.7, 43.5), (7.9, 43.5), (7.9, 39), (15.3, 39), (15.3, 51.5), (0, 51.5)], 0);
        _profile(const [(51.5, 15.3), (57.5, 9.5), (84, 15.3), (89, 20), (96, 20)]);
      case Role.knight:
        _knight();
        _profile(const [(82.5, 13.6), (84, 13.6), (89.5, 19.7), (96, 19.7)]);
      case Role.bishop:
        _profile(const [
          (20, 0), (24.5, 4.3), (27.5, 3.3), (29, 4.2), // finial
          (42.5, 12.7), (52, 9), // mitre
          (56, 13), (61.5, 7.5), // collar
          (84, 14.8), (89, 19.2), (96, 19.2), // body, skirt, base
        ]);
      case Role.queen:
        _profile(const [(15, 0), (21, 5.1), (24.5, 3.7), (27, 5)]);
        _facet(const [(0, 27), (5, 27), (9, 33), (0, 33)], 0.6);
        _facet(const [(0, 33), (9, 33), (17.7, 29), (10.6, 47), (0, 47)], -0.25);
        _profile(const [(47, 10.6), (52.5, 14.3), (58.5, 8.4), (84, 16.6), (89.5, 22.2), (96, 22.2)]);
      case Role.king:
        _facet(const [(0, 4), (3.4, 4), (3.4, 21), (0, 21)], 0);
        _facet(const [(0, 9), (8.1, 9), (8.1, 16), (0, 16)], 0);
        _profile(const [
          (20.5, 3.4), (26.5, 15.5), (47, 9.7), // crown
          (51.5, 13.9), (57.5, 8.3), // collar
          (83, 15.8), (89, 21.6), (96, 21.6), // body, skirt, base
        ]);
    }
    canvas.restore();
  }

  void _knight() {
    const ear = Offset(54.5, 29);
    const ridge = Offset(57, 49);
    const throat = Offset(53, 51.5);
    const snoutTop = Offset(30.6, 51.5);
    const snoutBottom = Offset(30.6, 60.5);
    const chin = Offset(35, 62);
    const neckFront = Offset(36, 82.5);
    const neckMid = Offset(58, 82.5);
    const backTop = Offset(70, 46);
    const backBottom = Offset(70, 77);
    const neckBack = Offset(64, 82.5);
    _polygon(const [ear, ridge, snoutTop], palette.left.at(0.8));
    _polygon(const [snoutTop, ridge, throat, chin, snoutBottom], palette.left.at(-0.2));
    _polygon(const [throat, ridge, neckMid, neckFront], palette.left.at(0.5));
    _polygon(const [ear, backTop, ridge], palette.right.at(0.7));
    _polygon(const [ridge, backTop, backBottom, neckBack, neckMid], palette.right.at(0));
  }

  void _profile(List<(double, double)> points) {
    for (var i = 0; i + 1 < points.length; i++) {
      final (y0, w0) = points[i];
      final (y1, w1) = points[i + 1];
      final tilt = ((w1 - w0) / (y1 - y0) * 1.2).clamp(-1.0, 1.0);
      _facet([(0, y0), (w0, y0), (w1, y1), (0, y1)], tilt);
    }
  }

  /// [half] is the left half as (half-width, y) points; mirrored to the right.
  void _facet(List<(double, double)> half, double tilt) {
    _polygon([for (final (w, y) in half) Offset(50 - w, y)], palette.left.at(tilt));
    _polygon([for (final (w, y) in half) Offset(50 + w, y)], palette.right.at(tilt));
  }

  void _polygon(List<Offset> points, Color color) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color);
    // Hairline in the same tone hides anti-aliasing seams between facets.
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.35
        ..strokeJoin = StrokeJoin.round,
    );
  }
}
