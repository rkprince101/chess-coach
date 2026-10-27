import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings.dart';
import 'board_theme.dart';

/// Thin wrapper around chessground's [Chessboard] that owns the controller
/// and pushes new positions into it whenever the parent rebuilds.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.position,
    required this.size,
    required this.orientation,
    required this.interactiveSide,
    required this.onMove,
    this.lastMove,
    this.shapes = const {},
  });

  final Position position;
  final double size;
  final Side orientation;

  /// Which side the user may move, or null for a read-only board.
  final Side? interactiveSide;
  final void Function(Move move) onMove;
  final Move? lastMove;
  final Set<Shape> shapes;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  late final ChessboardController _controller = ChessboardController(game: _gameData());

  GameData _gameData() {
    final pos = widget.position;
    final side = widget.interactiveSide;
    return GameData(
      fen: pos.fen,
      lastMove: widget.lastMove,
      playerSide: side == null
          ? PlayerSide.none
          : side == Side.white
              ? PlayerSide.white
              : PlayerSide.black,
      sideToMove: pos.turn,
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
      validMoves: makeLegalMoves(pos),
    );
  }

  @override
  void didUpdateWidget(covariant BoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position.fen != widget.position.fen ||
        oldWidget.lastMove != widget.lastMove ||
        oldWidget.interactiveSide != widget.interactiveSide) {
      _controller.updatePosition(_gameData(), resetPremove: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Seed from settings rather than the live scheme: the scheme lerps during
    // theme animations, which would rebuild the board palette every frame.
    final seed = Provider.of<SettingsController?>(context)?.themeSeedColor ??
        theme.colorScheme.primary.toARGB32();
    final board = BoardTheme.of(seed: seed, brightness: theme.brightness);
    return Chessboard(
      controller: _controller,
      size: widget.size,
      orientation: widget.orientation,
      shapes: widget.shapes,
      settings: ChessboardSettings(
        colorScheme: board.colorScheme,
        pieceAssets: BoardTheme.pieceAssets,
        enablePremoves: false,
        autoQueenPromotion: false,
        // M3 standard easing duration for on-screen movement.
        animationDuration: const Duration(milliseconds: 250),
        // Shape: large (16dp). Elevation comes from the tonal squares, not a shadow.
        borderRadius: BorderRadius.circular(16),
        drawShape: DrawShapeOptions(
          enable: true,
        ),
      ),
      onMove: (move, {viaDragAndDrop}) => widget.onMove(move),
    );
  }
}
