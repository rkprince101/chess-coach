import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../analysis/game_analysis.dart';
import '../../engine/engine_service.dart';
import '../../models/move_quality.dart';
import '../../services/match_history.dart';
import '../../services/settings.dart';
import '../../state/analysis_controller.dart';
import '../fonts.dart';
import '../layout.dart';
import '../widgets/board_view.dart';
import '../widgets/eval_bar.dart';
import '../widgets/eval_graph.dart';
import '../widgets/expressive_dialog.dart';
import '../widgets/segmented_list.dart';
import 'history_screen.dart' show formatMatchDate, matchTitle;

/// Move-by-move engine analysis of a recorded game: accuracy for both
/// players, an evaluation graph, a grade for every move and the engine's
/// better line wherever a move went wrong.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.record});

  final MatchRecord record;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late final AnalysisController _c;

  @override
  void initState() {
    super.initState();
    _c = AnalysisController(
      record: widget.record,
      engine: context.read<EngineService>(),
      history: Provider.of<MatchHistory?>(context, listen: false),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _analyse() {
    final strength = context.read<SettingsController>().analysisStrength;
    _c.analyse(timeMs: strength.timeMs);
  }

  Future<void> _copyPgn() async {
    await Clipboard.setData(ClipboardData(text: _c.record.toPgn()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PGN copied to the clipboard')));
  }

  Future<void> _delete(MatchHistory history) async {
    final ok = await confirmDeleteMatch(context);
    if (ok != true) return;
    await history.delete(_c.record.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final history = Provider.of<MatchHistory?>(context);
    final saved = history?.byId(widget.record.id) != null;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Game analysis'),
          centerTitle: false,
          actions: [
            IconButton(tooltip: 'Copy PGN', icon: const Icon(Icons.content_copy_rounded), onPressed: _copyPgn),
            if (saved)
              IconButton(
                tooltip: 'Delete game',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _delete(history!),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): _c.previous,
              const SingleActivator(LogicalKeyboardKey.arrowRight): _c.next,
              const SingleActivator(LogicalKeyboardKey.home): _c.first,
              const SingleActivator(LogicalKeyboardKey.end): _c.last,
            },
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (isWideLayout(constraints)) {
                    final boardSize = math.max(200.0, sideBySideBoardSize(constraints) - 56);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _boardWithBar(boardSize, vertical: true),
                              const SizedBox(height: 8),
                              _NavRow(c: _c),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _Panel(
                            c: _c,
                            onAnalyse: _analyse,
                            padding: withSystemInsets(context, const EdgeInsets.fromLTRB(0, 16, 24, 16)),
                          ),
                        ),
                      ],
                    );
                  }
                  final boardSize = stackedBoardSize(constraints, heightFraction: 0.48);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: _boardWithBar(boardSize, vertical: false),
                      ),
                      _NavRow(c: _c),
                      Expanded(
                        child: _Panel(
                          c: _c,
                          onAnalyse: _analyse,
                          padding: withSystemInsets(context, const EdgeInsets.fromLTRB(12, 0, 12, 16)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardWithBar(double size, {required bool vertical}) {
    final board = BoardView(
      position: _c.position,
      lastMove: _c.lastMove,
      size: size,
      orientation: _c.record.playerSide,
      interactiveSide: null,
      shapes: _c.shapes,
      onMove: (_) {},
    );
    if (_c.analysis == null) return board;
    if (vertical) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EvalBar(cpWhite: _c.evalCpWhite, height: size, orientation: _c.record.playerSide, label: _c.evalText),
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
          cpWhite: _c.evalCpWhite,
          width: size,
          orientation: _c.record.playerSide,
          label: _c.evalText,
        ),
      ],
    );
  }
}

/// Asks before deleting a saved game; true when confirmed.
Future<bool?> confirmDeleteMatch(BuildContext context, {bool all = false}) {
  final scheme = Theme.of(context).colorScheme;
  return showExpressiveDialog<bool>(
    context: context,
    builder: (context) => ExpressiveDialog(
      icon: Icons.delete_outline_rounded,
      iconColor: scheme.onErrorContainer,
      badgeColor: scheme.errorContainer,
      title: all ? 'Delete all games?' : 'Delete this game?',
      message: all
          ? 'Every saved game and its analysis will be removed from this device. This cannot be undone.'
          : 'The game and its analysis will be removed from this device. This cannot be undone.',
      actions: [
        ExpressiveDialog.destructive(
          icon: Icons.delete_outline_rounded,
          label: all ? 'Delete all' : 'Delete',
          onPressed: () => Navigator.pop(context, true),
        ),
        ExpressiveDialog.secondary(
          icon: Icons.close_rounded,
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    ),
  );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.c});

  final AnalysisController c;

  @override
  Widget build(BuildContext context) {
    final hasMistakes = c.analysis?.plies.any((p) => p.quality.isBad) ?? false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Start',
          icon: const Icon(Icons.first_page_rounded),
          onPressed: c.atStart ? null : c.first,
        ),
        IconButton(
          tooltip: 'Previous move',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: c.atStart ? null : c.previous,
        ),
        IconButton(
          tooltip: 'Next move',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: c.atEnd ? null : c.next,
        ),
        IconButton(
          tooltip: 'End',
          icon: const Icon(Icons.last_page_rounded),
          onPressed: c.atEnd ? null : c.last,
        ),
        if (hasMistakes)
          IconButton(
            tooltip: 'Next mistake',
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: c.nextMistake,
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.c, required this.onAnalyse, required this.padding});

  final AnalysisController c;
  final VoidCallback onAnalyse;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final a = c.analysis;
    return ListView(
      padding: padding,
      children: [
        _Header(record: c.record),
        const SizedBox(height: 12),
        if (a == null)
          _AnalyseCard(c: c, onAnalyse: onAnalyse)
        else ...[
          _Accuracy(analysis: a, player: c.record.playerSide),
          const SizedBox(height: 12),
          EvalGraph(
            evalCp: a.evalCp,
            qualities: [for (final p in a.plies) p.quality],
            selected: c.ply,
            onSelect: c.goTo,
          ),
          const SizedBox(height: 12),
          _MoveVerdict(c: c),
        ],
        const SegmentHeader('Moves'),
        SegmentedList(
          children: [
            Padding(padding: const EdgeInsets.all(14), child: _MoveChips(c: c)),
          ],
        ),
        if (a != null) ...[
          const SegmentHeader('Move grades'),
          _Breakdown(analysis: a, player: c.record.playerSide),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: c.running ? null : onAnalyse,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(c.running
                    ? 'Analysing… ${c.progressDone}/${c.progressTotal}'
                    : 'Analyse again (${context.watch<SettingsController>().analysisStrength.label.toLowerCase()})'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.record});

  final MatchRecord record;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final you = record.playerSide == Side.white ? 'White' : 'Black';
    final opponent = record.opponentElo == null ? 'the computer' : 'the computer (${record.opponentElo})';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(matchTitle(record), style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            [
              'You played $you vs $opponent',
              if (record.opening != null) record.opening!,
              formatMatchDate(record.startedAt),
            ].join(' • '),
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AnalyseCard extends StatelessWidget {
  const _AnalyseCard({required this.c, required this.onAnalyse});

  final AnalysisController c;
  final VoidCallback onAnalyse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strength = context.watch<SettingsController>().analysisStrength;
    final seconds = (c.positions.length * strength.timeMs / 1000).ceil();
    final estimate = seconds < 60 ? '$seconds s' : '${(seconds / 60).ceil()} min';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('Full game analysis', style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            if (c.moves.isEmpty)
              Text('No moves were played in this game.', style: text.bodyMedium)
            else if (c.running) ...[
              Text('Analysing position ${math.min(c.progressDone + 1, c.progressTotal)} of ${c.progressTotal}…',
                  style: text.bodyMedium),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: c.progressTotal == 0 ? null : c.progressDone / c.progressTotal),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: c.cancel, child: const Text('Cancel')),
              ),
            ] else ...[
              Text(
                'The engine checks every move of both players, on this device. You get accuracy scores, '
                'an evaluation graph and a grade for each move, from Brilliant to Blunder, with the better '
                'line wherever a move went wrong. ${strength.label} strength, about $estimate.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (c.error != null) ...[
                const SizedBox(height: 8),
                Text(c.error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAnalyse,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Analyse game'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Accuracy extends StatelessWidget {
  const _Accuracy({required this.analysis, required this.player});

  final GameAnalysis analysis;
  final Side player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String value(Side s) => analysis.accuracy(s)?.toStringAsFixed(1) ?? '—';
    String label(Side s) => '${s == Side.white ? 'White' : 'Black'}${s == player ? ' (you)' : ''} accuracy';
    return TileGrid(
      rows: [
        [
          for (final s in Side.values)
            StatTile(
              icon: s == Side.white ? Icons.circle_outlined : Icons.circle,
              value: '${value(s)}%',
              label: label(s),
              valueColor: s == player ? scheme.primary : null,
            ),
        ],
      ],
    );
  }
}

class _MoveVerdict extends StatelessWidget {
  const _MoveVerdict({required this.c});

  final AnalysisController c;

  static String _describe(MoveQuality q) => switch (q) {
        MoveQuality.brilliant => 'A sacrifice that works: the engine agrees it is the strongest idea.',
        MoveQuality.great => 'The only good move in the position.',
        MoveQuality.best => "The engine's top choice.",
        MoveQuality.excellent => 'Practically as strong as the best move.',
        MoveQuality.good => 'A solid move, a little weaker than the best.',
        MoveQuality.book => 'A known opening move.',
        MoveQuality.forced => 'The only legal move.',
        MoveQuality.inaccuracy => 'A slightly weaker move that gives a little away.',
        MoveQuality.mistake => 'This lets a good part of the advantage slip.',
        MoveQuality.miss => 'The opponent had just gone wrong, and this move let the chance go.',
        MoveQuality.blunder => 'A serious error that swings the game.',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mono = monoFamily(context);
    final ply = c.currentPly;
    final i = c.ply - 1;
    final Widget body;
    if (ply == null) {
      body = Text('Starting position. Step through the moves or tap the graph.', style: text.bodyMedium);
    } else {
      final before = c.positions[i];
      final number = '${before.fullmoves}${before.turn == Side.white ? '.' : '...'}';
      final showBest = ply.bestSan != null && ply.bestUci != c.moves[i].uci;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ply.quality.icon, color: ply.quality.color, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$number ${c.sans[i]}', style: TextStyle(fontFamily: mono)),
                    TextSpan(text: '  ${ply.quality.label}', style: TextStyle(color: ply.quality.color)),
                  ]),
                  style: text.titleMedium,
                ),
              ),
              const Spacer(),
              if (c.evalText != null)
                Text(c.evalText!, style: text.labelLarge?.copyWith(fontFamily: mono)),
            ],
          ),
          const SizedBox(height: 6),
          Text(_describe(ply.quality), style: text.bodyMedium),
          if (showBest) ...[
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Best was '),
                TextSpan(
                  text: ply.bestSan,
                  style: TextStyle(fontFamily: mono, fontWeight: FontWeight.w700, color: scheme.primary),
                ),
                if (ply.bestLine.isNotEmpty) ...[
                  const TextSpan(text: '  •  '),
                  TextSpan(text: ply.bestLine, style: TextStyle(fontFamily: mono, color: scheme.onSurfaceVariant)),
                ],
              ]),
              style: text.bodyMedium,
            ),
          ],
        ],
      );
    }
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: body));
  }
}

class _MoveChips extends StatelessWidget {
  const _MoveChips({required this.c});

  final AnalysisController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = monoFamily(context);
    if (c.moves.isEmpty) return Text('No moves.', style: TextStyle(color: scheme.outline));
    final whiteFirst = c.positions.first.turn == Side.white;
    final startMove = c.positions.first.fullmoves;
    return Wrap(
      spacing: 2,
      runSpacing: 4,
      children: [
        for (var i = 0; i < c.moves.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => c.goTo(i + 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: c.ply == i + 1 ? scheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_number(i, whiteFirst, startMove)}${c.sans[i]}',
                    style: TextStyle(
                      fontFamily: mono,
                      fontWeight: c.ply == i + 1 ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (c.qualityOf(i) case final q?) ...[
                    const SizedBox(width: 3),
                    Tooltip(message: q.label, child: Icon(q.icon, size: 13, color: q.color)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// "12. " before White's moves, plus "12... " on a game that starts with Black.
  static String _number(int i, bool whiteFirst, int startMove) {
    final whiteMove = whiteFirst ? i.isEven : i.isOdd;
    final n = startMove + (whiteFirst ? i ~/ 2 : (i + 1) ~/ 2);
    if (whiteMove) return '$n. ';
    return i == 0 ? '$n... ' : '';
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.analysis, required this.player});

  final GameAnalysis analysis;
  final Side player;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final white = analysis.counts(Side.white);
    final black = analysis.counts(Side.black);
    final rows = [for (final q in MoveQuality.values) if ((white[q] ?? 0) + (black[q] ?? 0) > 0) q];
    Widget count(int? n, Color? color) => SizedBox(
          width: 64,
          child: Text('${n ?? 0}',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: (n ?? 0) == 0 ? scheme.outline : color)),
        );
    return SegmentedList(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(child: SizedBox()),
              for (final s in Side.values)
                SizedBox(
                  width: 64,
                  child: Text(
                    '${s == Side.white ? 'White' : 'Black'}${s == player ? '\n(you)' : ''}',
                    textAlign: TextAlign.center,
                    style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        for (final q in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(q.icon, color: q.color, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(q.label, style: text.bodyLarge)),
                count(white[q], q.color),
                count(black[q], q.color),
              ],
            ),
          ),
      ],
    );
  }
}
