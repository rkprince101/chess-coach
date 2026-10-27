import 'dart:async';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/coach_service.dart';
import '../../engine/engine_service.dart';
import '../../models/move_quality.dart';
import '../../services/saved_game.dart';
import '../../services/settings.dart';
import '../../state/game_controller.dart';
import '../../voice/voice_service.dart';
import '../layout.dart';
import '../widgets/voice_button.dart';
import '../widgets/board_view.dart';
import '../widgets/coach_feed.dart';
import '../widgets/eval_bar.dart';
import '../widgets/expressive_dialog.dart';
import '../widgets/move_list.dart';
import 'settings_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, this.controller});

  /// Optional pre-built controller (used by tests); the screen owns and
  /// starts its own game otherwise.
  final GameController? controller;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late final GameController _game;
  late final bool _ownsController;
  bool _gameOverShown = false;

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    _ownsController = injected == null;
    _game =
        injected ??
        GameController(
          engine: context.read<EngineService>(),
          coach: context.read<CoachService>(),
          settings: context.read<SettingsController>(),
          voice: context.read<VoiceService>(),
        );
    _game.addListener(_onGameChanged);
    if (_ownsController) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  /// Resumes the game saved on the last exit, if any; otherwise starts fresh.
  Future<void> _start() async {
    final saved = await SavedGameStore.load();
    if (!mounted) return;
    if (saved == null) {
      _game.newGame();
      return;
    }
    // Once resumed the game lives in memory; leaving asks again.
    unawaited(SavedGameStore.clear());
    _game.resumeGame(saved);
  }

  /// Back while a game is running: save it for later, discard it, or stay.
  Future<void> _confirmLeave() async {
    final moves = (_game.history.length + 1) ~/ 2;
    final opening = _game.openingName;
    final choice = await showExpressiveDialog<_LeaveChoice>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return ExpressiveDialog(
          icon: Icons.pause_rounded,
          iconColor: scheme.onTertiaryContainer,
          badgeColor: scheme.tertiaryContainer,
          title: 'Leave this game?',
          message: 'Save it to pick up right where you left off, or discard it and start fresh next time.',
          content: TileGrid(
            rows: [
              [
                StatTile(icon: Icons.tag_rounded, value: '$moves', label: moves == 1 ? 'Move played' : 'Moves played'),
                StatTile(
                  icon: _game.playerSide == Side.white ? Icons.circle_outlined : Icons.circle,
                  value: _game.playerSide == Side.white ? 'White' : 'Black',
                  label: 'You play',
                ),
              ],
              if (opening != null) [StatTile(icon: Icons.menu_book_rounded, value: opening, label: 'Opening')],
            ],
          ),
          actions: [
            ExpressiveDialog.primary(
              icon: Icons.bookmark_add_rounded,
              label: 'Save & exit',
              onPressed: () => Navigator.pop(context, _LeaveChoice.save),
            ),
            ExpressiveDialog.secondary(
              icon: Icons.play_arrow_rounded,
              label: 'Keep playing',
              onPressed: () => Navigator.pop(context, _LeaveChoice.stay),
            ),
            ExpressiveDialog.destructive(
              icon: Icons.delete_outline_rounded,
              label: 'Discard game',
              onPressed: () => Navigator.pop(context, _LeaveChoice.discard),
            ),
          ],
        );
      },
    );
    switch (choice) {
      case _LeaveChoice.save:
        await SavedGameStore.save(_game.snapshot());
      case _LeaveChoice.discard:
        await SavedGameStore.clear();
      case _LeaveChoice.stay || null:
        return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    if (_ownsController) _game.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    if (_game.phase != GamePhase.gameOver) {
      _gameOverShown = false;
      return;
    }
    if (_gameOverShown) return;
    _gameOverShown = true;
    // Let the final move land on the board before the dialog covers it.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _game.phase == GamePhase.gameOver) _showGameOver();
    });
  }

  Future<void> _showGameOver() async {
    final playAgain = await showExpressiveDialog<bool>(
      context: context,
      builder: (_) => _GameOverDialog(game: _game),
    );
    if (playAgain == true && mounted) _pickSideAndStart();
  }

  Future<void> _confirmNewGame() async {
    if (_game.history.isEmpty || _game.phase == GamePhase.gameOver) {
      _pickSideAndStart();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new game?'),
        content: const Text('The current game will be abandoned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('New game')),
        ],
      ),
    );
    if (ok == true) _pickSideAndStart();
  }

  Future<void> _pickSideAndStart() async {
    final side = await showModalBottomSheet<Side>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Play as', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.circle_outlined),
              title: const Text('White'),
              onTap: () => Navigator.pop(context, Side.white),
            ),
            ListTile(
              leading: const Icon(Icons.circle),
              title: const Text('Black'),
              onTap: () => Navigator.pop(context, Side.black),
            ),
            ListTile(
              leading: const Icon(Icons.shuffle_rounded),
              title: const Text('Random'),
              onTap: () => Navigator.pop(context, math.Random().nextBool() ? Side.white : Side.black),
            ),
          ],
        ),
      ),
    );
    if (side != null) _game.newGame(side: side);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return ListenableBuilder(
      listenable: _game,
      builder: (context, _) {
        final showCoachPanel = settings.coachEnabled && settings.showCoachDetails;
        return PopScope(
          canPop: !_game.isInProgress,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Play & Learn'),
              centerTitle: false,
              actions: [
                const VoiceButton(),
                IconButton(
                  tooltip: 'New game',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _confirmNewGame,
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (isWideLayout(constraints)) {
                    // Without the side panel, controls sit under the board instead.
                    final boardSize = showCoachPanel
                        ? sideBySideBoardSize(constraints)
                        : math.max(200.0, math.min(sideBySideBoardSize(constraints), constraints.maxHeight - 160));
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _boardWithBar(boardSize, settings, vertical: true),
                              if (!showCoachPanel) _QuickActions(game: _game, width: boardSize),
                            ],
                          ),
                        ),
                        if (showCoachPanel)
                          Expanded(
                            child: _SidePanel(game: _game, compact: isCompactWidth(constraints)),
                          )
                        else
                          const Spacer(),
                      ],
                    );
                  }
                  final boardSize = stackedBoardSize(constraints, heightFraction: showCoachPanel ? 0.5 : 0.7);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                        child: _boardWithBar(boardSize, settings, vertical: false),
                      ),
                      if (showCoachPanel)
                        Expanded(child: _SidePanel(game: _game, compact: true))
                      else
                        _QuickActions(game: _game, width: boardSize),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _boardWithBar(double size, SettingsController settings, {required bool vertical}) {
    final board = BoardView(
      position: _game.displayedPosition,
      lastMove: _game.displayedLastMove,
      size: size,
      orientation: _game.playerSide,
      interactiveSide: _game.canPlayerMove ? _game.playerSide : null,
      shapes: _game.displayedShapes,
      onMove: _game.onPlayerMove,
    );
    if (!settings.showEvalBar) return board;
    if (vertical) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EvalBar(cpWhite: _game.evalCpWhite, height: size, orientation: _game.playerSide, label: _game.evalText),
          const SizedBox(width: 8),
          board,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        board,
        const SizedBox(height: 4),
        EvalBar.horizontal(
          cpWhite: _game.evalCpWhite,
          width: size,
          orientation: _game.playerSide,
          label: _game.evalText,
        ),
      ],
    );
  }
}

enum _LeaveChoice { save, discard, stay }

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.game, this.compact = false});

  final GameController game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastReview = game.playerReviews.isEmpty ? null : game.playerReviews.last;
    final coaching = game.phase == GamePhase.coaching && game.pendingReview != null;
    final showCoach = game.coachEnabled && context.read<SettingsController>().showCoachDetails;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 10 : 0, compact ? 2 : 16, compact ? 10 : 16, compact ? 4 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusRow(game: game, compact: compact),
              SizedBox(height: compact ? 4 : 8),
              if (game.preview != null) ...[
                _PreviewPanel(game: game, compact: compact),
                SizedBox(height: compact ? 4 : 8),
              ],
              if (coaching) _CoachingPrompt(game: game, compact: compact) else _ActionRow(game: game, compact: compact),
              if (lastReview != null && !coaching && !compact) ...[
                const SizedBox(height: 6),
                _QualityChip(review: lastReview, game: game),
              ],
              SizedBox(height: compact ? 4 : 8),
              if (compact)
                MoveStrip(history: game.history, viewIndex: game.viewIndex, onSelect: game.viewPly)
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 110),
                  child: SingleChildScrollView(
                    child: MoveList(history: game.history, viewIndex: game.viewIndex, onSelect: game.viewPly),
                  ),
                ),
            ],
          ),
        ),
        if (showCoach) ...[
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: CoachFeed(
              messages: game.messages,
              onAsk: game.ask,
              hint: compact ? 'Ask the coach…' : 'Ask the coach anything about this position…',
            ),
          ),
        ],
      ],
    );
  }
}

/// End-of-game summary: result, how it ended, stats, move quality breakdown
/// and (when the coach is on) the coach's summary as it streams in.
class _GameOverDialog extends StatelessWidget {
  const _GameOverDialog({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final winner = game.winner;
        final (title, icon, fg, bg) = winner == null
            ? ('Draw', Icons.handshake_rounded, scheme.onSecondaryContainer, scheme.secondaryContainer)
            : winner == game.playerSide
            ? ('You won!', Icons.emoji_events_rounded, scheme.onPrimaryContainer, scheme.primaryContainer)
            : ('You lost', Icons.flag_rounded, scheme.onErrorContainer, scheme.errorContainer);
        final reviews = game.playerReviews;
        final opening = game.openingName;
        final summary = _summary();
        final white = game.playerSide == Side.white;
        return ExpressiveDialog(
          icon: icon,
          iconColor: fg,
          badgeColor: bg,
          title: title,
          message: game.gameOverText,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileGrid(
                rows: [
                  [
                    StatTile(icon: Icons.sports_score_rounded, value: game.endReason ?? '—', label: 'Ended by'),
                    StatTile(icon: Icons.tag_rounded, value: '${(game.history.length + 1) ~/ 2}', label: 'Moves'),
                  ],
                  [
                    StatTile(
                      icon: white ? Icons.circle_outlined : Icons.circle,
                      value: white ? 'White' : 'Black',
                      label: 'You played',
                    ),
                    StatTile(
                      icon: Icons.track_changes_rounded,
                      value: reviews.isEmpty ? '—' : '${game.accuracy.toStringAsFixed(0)}%',
                      label: 'Accuracy',
                      valueColor: reviews.isNotEmpty && game.accuracy >= 80 ? scheme.primary : null,
                    ),
                  ],
                  if (opening != null) [StatTile(icon: Icons.menu_book_rounded, value: opening, label: 'Opening')],
                ],
              ),
              if (reviews.isNotEmpty) ...[const SizedBox(height: 20), _QualityBreakdown(reviews: reviews)],
              if (summary != null) ...[const SizedBox(height: 20), _CoachTake(message: summary)],
            ],
          ),
          actions: [
            ExpressiveDialog.primary(
              icon: Icons.replay_rounded,
              label: 'New game',
              onPressed: () => Navigator.pop(context, true),
            ),
            ExpressiveDialog.secondary(
              icon: Icons.manage_search_rounded,
              label: 'Review game',
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        );
      },
    );
  }

  /// The coach's end-of-game message, posted after the game-over notice.
  CoachMessage? _summary() {
    final start = game.gameOverMessageIndex;
    if (start == null) return null;
    return game.messages.skip(start).where((m) => m.kind == CoachMessageKind.coach).firstOrNull;
  }
}

/// Proportional bar of the player's move grades with a legend.
class _QualityBreakdown extends StatelessWidget {
  const _QualityBreakdown({required this.reviews});

  final List<MoveReview> reviews;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final counts = [
      for (final q in MoveQuality.values)
        if (reviews.where((r) => r.quality == q).length case final n when n > 0) (q, n),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your moves', style: text.titleSmall),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (q, n)) in counts.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(flex: n, child: ColoredBox(color: q.color)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final (q, n) in counts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(q.icon, size: 16, color: q.color),
                  const SizedBox(width: 4),
                  Text('$n ${q.label}', style: text.labelLarge),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// The coach's summary in its own tile, with a progress bar while it streams.
class _CoachTake extends StatelessWidget {
  const _CoachTake({required this.message});

  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: dialogTileColor(scheme), borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: scheme.tertiaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.school_rounded, size: 20, color: scheme.onTertiaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Coach's take", style: text.titleSmall),
                const SizedBox(height: 6),
                if (message.text.isEmpty)
                  const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator())
                else
                  Text(message.text, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hint / take back / resign under the board when the coach panel is hidden,
/// plus the current hint text (otherwise it would only reach the hidden feed).
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.game, required this.width});

  final GameController game;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tip = game.hintLevel == 0
        ? null
        : game.messages.where((m) => m.kind == CoachMessageKind.tip).lastOrNull?.text;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActionRow(game: game, compact: true),
            if (tip != null && tip.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  tip,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.game, required this.compact});

  final GameController game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastReview = game.playerReviews.isEmpty ? null : game.playerReviews.last;
    final (text, icon) = switch (game.phase) {
      GamePhase.playerTurn => ('Your move', Icons.touch_app_outlined),
      GamePhase.analyzing => ('Checking your move…', Icons.search_rounded),
      GamePhase.coaching => ('Coach wants a word', Icons.school_rounded),
      GamePhase.engineThinking => ('Opponent is thinking…', Icons.hourglass_top_rounded),
      GamePhase.gameOver => (game.gameOverText ?? 'Game over', Icons.flag_rounded),
    };
    final busy = game.phase == GamePhase.analyzing || game.phase == GamePhase.engineThinking;
    final subtitle = [
      if (game.openingName != null) game.openingName!,
      if (compact && lastReview != null && game.phase != GamePhase.coaching)
        '${lastReview.san}: ${lastReview.quality.label}',
    ].join('  ·  ');
    return Row(
      children: [
        if (busy)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (game.playerReviews.isNotEmpty)
          Tooltip(
            message: 'Your accuracy so far',
            child: Text(
              '${game.accuracy.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.game, required this.compact});

  final GameController game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final canAct = game.canPlayerMove;
    final canTakeBack = (canAct || game.phase == GamePhase.gameOver) && game.history.isNotEmpty;
    final hintLabel = game.hintLevel == 0 ? 'Hint' : 'Hint ${math.min(game.hintLevel + 1, 3)}/3';

    if (compact) {
      return Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: canAct ? game.requestHint : null,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
            label: Text(hintLabel),
          ),
          if (game.hintLevel >= 3 && canAct) ...[
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: game.showHintLine,
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text('Show me'),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Take back',
            onPressed: canTakeBack ? game.takeBackFullMove : null,
            icon: const Icon(Icons.undo_rounded),
            visualDensity: VisualDensity.compact,
          ),
          if (game.phase != GamePhase.gameOver)
            IconButton(
              tooltip: 'Resign',
              onPressed: game.history.isNotEmpty ? game.resign : null,
              icon: const Icon(Icons.flag_outlined),
              visualDensity: VisualDensity.compact,
            ),
        ],
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilledButton.tonalIcon(
          onPressed: canAct ? game.requestHint : null,
          icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
          label: Text(hintLabel),
        ),
        if (game.hintLevel >= 3 && canAct)
          FilledButton.tonalIcon(
            onPressed: game.showHintLine,
            icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const Text('Show me'),
          ),
        OutlinedButton.icon(
          onPressed: canTakeBack ? game.takeBackFullMove : null,
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: const Text('Take back'),
        ),
        if (game.phase != GamePhase.gameOver)
          OutlinedButton.icon(
            onPressed: game.history.isNotEmpty ? game.resign : null,
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Resign'),
          ),
      ],
    );
  }
}

class _CoachingPrompt extends StatelessWidget {
  const _CoachingPrompt({required this.game, required this.compact});

  final GameController game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final review = game.pendingReview!;
    final q = review.quality;
    final dense = FilledButton.styleFrom(visualDensity: VisualDensity.compact);
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: q.color.withValues(alpha: 0.10),
        border: Border.all(color: q.color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(q.icon, color: q.color, size: compact ? 20 : 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${q.label}: ${review.san}  (${review.evalBefore} → ${review.evalAfter})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: q.color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(
              'Want to try a different approach? Watch the board, read the coach\'s note, then decide.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          SizedBox(height: compact ? 6 : 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: game.retryMove,
                style: compact ? dense : null,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(compact ? 'Retry' : 'Take back & retry'),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: game.keepMove,
                style: compact ? OutlinedButton.styleFrom(visualDensity: VisualDensity.compact) : null,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(compact ? 'Keep' : 'Keep my move'),
              ),
              const Spacer(),
              if (review.punishingMoves.isNotEmpty)
                IconButton(
                  tooltip: 'Show what happens',
                  onPressed: () => game.showPunishment(review),
                  icon: const Icon(Icons.visibility_outlined),
                  visualDensity: VisualDensity.compact,
                ),
              if (review.bestMoves.isNotEmpty)
                IconButton(
                  tooltip: 'Show a better idea',
                  onPressed: () => game.showBetterLine(review),
                  icon: const Icon(Icons.tips_and_updates_outlined),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.review, required this.game});

  final MoveReview review;
  final GameController game;

  @override
  Widget build(BuildContext context) {
    final q = review.quality;
    final showBest = q.isBad && review.bestSan != null;
    final canShow = q.isBad && review.punishingMoves.isNotEmpty && game.phase != GamePhase.engineThinking;
    return Row(
      children: [
        Icon(q.icon, size: 16, color: q.color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${review.san}: ${q.label}${showBest ? '  ·  better: ${review.bestSan}' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: q.color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (canShow)
          TextButton(
            onPressed: () => game.showPunishment(review),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Show why'),
          ),
      ],
    );
  }
}

/// Playback controls for a line the coach is replaying on the board.
class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.game, required this.compact});

  final GameController game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pv = game.preview!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 12, compact ? 6 : 10, 4, compact ? 4 : 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.movie_outlined, size: 18, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pv.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.error),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${pv.index} / ${pv.moves.length}', style: Theme.of(context).textTheme.labelMedium),
              IconButton(
                tooltip: 'Back to the game',
                onPressed: game.closePreview,
                icon: const Icon(Icons.close_rounded, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text(
            pv.narration,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: compact ? 2 : 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Previous move',
                onPressed: pv.atStart ? null : game.previewPrevious,
                icon: const Icon(Icons.skip_previous_rounded),
                visualDensity: VisualDensity.compact,
              ),
              IconButton.filled(
                tooltip: pv.autoPlaying ? 'Pause' : 'Play',
                onPressed: game.previewTogglePlay,
                icon: Icon(pv.autoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                visualDensity: VisualDensity.compact,
              ),
              IconButton.filledTonal(
                tooltip: 'Next move',
                onPressed: pv.atEnd ? null : game.previewNext,
                icon: const Icon(Icons.skip_next_rounded),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: game.closePreview,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Back to game'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
