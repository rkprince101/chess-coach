import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/match_history.dart';
import '../../services/settings.dart';
import '../layout.dart';
import '../widgets/expressive_dialog.dart';
import '../widgets/segmented_list.dart';
import 'analysis_screen.dart';

/// Every game saved on this device, newest first. Opening one shows its
/// full analysis.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(context.read<MatchHistory>().load());
  }

  void _open(MatchRecord record) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AnalysisScreen(record: record)));
  }

  Future<void> _copyPgn(MatchRecord record) async {
    await Clipboard.setData(ClipboardData(text: record.toPgn()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PGN copied to the clipboard')));
  }

  Future<void> _delete(MatchHistory history, MatchRecord record) async {
    if (await confirmDeleteMatch(context) == true) await history.delete(record.id);
  }

  Future<void> _clear(MatchHistory history) async {
    if (await confirmDeleteMatch(context, all: true) == true) await history.clear();
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<MatchHistory>();
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final records = history.records;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game history'),
        centerTitle: false,
        actions: [
          if (records.isNotEmpty)
            IconButton(
              tooltip: 'Delete all games',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _clear(history),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: !history.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: withSystemInsets(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
                  children: [
                    if (!settings.saveMatchHistory)
                      Card(
                        color: scheme.tertiaryContainer,
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          value: false,
                          title: Text('Saving is off', style: TextStyle(color: scheme.onTertiaryContainer)),
                          subtitle: Text(
                            'New games are not being recorded. Turn this on to keep them.',
                            style: TextStyle(color: scheme.onTertiaryContainer.withValues(alpha: 0.8)),
                          ),
                          onChanged: settings.setSaveMatchHistory,
                        ),
                      ),
                    if (records.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
                        child: Column(
                          children: [
                            Icon(Icons.history_rounded, size: 56, color: scheme.outline),
                            const SizedBox(height: 16),
                            Text('No games yet', style: text.titleLarge),
                            const SizedBox(height: 8),
                            Text(
                              'Games you play in Play & Learn are saved here with all their moves. '
                              'Open one to analyse it move by move.',
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      const SizedBox(height: 8),
                      _Totals(records: records),
                      const SegmentHeader('Games'),
                      SegmentedList(
                        children: [
                          for (final r in records)
                            _MatchTile(
                              record: r,
                              onTap: () => _open(r),
                              onCopy: () => _copyPgn(r),
                              onDelete: () => _delete(history, r),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.records});

  final List<MatchRecord> records;

  @override
  Widget build(BuildContext context) {
    final finished = records.where((r) => r.finished);
    final wins = finished.where((r) => r.winner == r.playerSide).length;
    final losses = finished.where((r) => r.winner == r.playerSide.opposite).length;
    final draws = finished.where((r) => r.winner == null).length;
    final accuracies = [
      for (final r in records)
        ?r.analysis?.accuracy(r.playerSide),
    ];
    return TileGrid(
      rows: [
        [
          StatTile(icon: Icons.sports_esports_rounded, value: '${records.length}', label: 'Games'),
          StatTile(
            icon: Icons.track_changes_rounded,
            value: accuracies.isEmpty
                ? '—'
                : '${(accuracies.reduce((a, b) => a + b) / accuracies.length).toStringAsFixed(0)}%',
            label: 'Avg. accuracy',
          ),
        ],
        [
          StatTile(icon: Icons.emoji_events_rounded, value: '$wins', label: 'Won'),
          StatTile(icon: Icons.handshake_rounded, value: '$draws', label: 'Drawn'),
          StatTile(icon: Icons.flag_rounded, value: '$losses', label: 'Lost'),
        ],
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.record, required this.onTap, required this.onCopy, required this.onDelete});

  final MatchRecord record;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (letter, fg, bg) = !record.finished
        ? ('–', scheme.onSurfaceVariant, scheme.surfaceContainerHighest)
        : record.winner == null
            ? ('½', scheme.onSecondaryContainer, scheme.secondaryContainer)
            : record.winner == record.playerSide
                ? ('W', scheme.onPrimaryContainer, scheme.primaryContainer)
                : ('L', scheme.onErrorContainer, scheme.errorContainer);
    final moves = (record.moves.length + 1) ~/ 2;
    final accuracy = record.analysis?.accuracy(record.playerSide);
    final details = [
      '$moves move${moves == 1 ? '' : 's'}',
      if (accuracy != null) 'accuracy ${accuracy.toStringAsFixed(0)}%',
      if (record.opening != null) record.opening!,
      formatMatchDate(record.startedAt),
    ].join(' • ');
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(letter, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg)),
      ),
      title: Text(matchTitle(record)),
      subtitle: Text(
        '${record.playerSide == Side.white ? 'White' : 'Black'} vs computer'
        '${record.opponentElo == null ? '' : ' (${record.opponentElo})'}\n$details',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.analysis != null)
            Tooltip(message: 'Analysed', child: Icon(Icons.analytics_rounded, size: 20, color: scheme.primary)),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: onCopy,
                child: const ListTile(leading: Icon(Icons.content_copy_rounded), title: Text('Copy PGN')),
              ),
              PopupMenuItem(
                value: onDelete,
                child: const ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "You won by checkmate", "Draw by stalemate", "Unfinished game", ...
String matchTitle(MatchRecord r) {
  if (!r.finished) return 'Unfinished game';
  final reason = r.endReason.toLowerCase();
  final by = reason.isEmpty || reason == 'draw' || reason == 'game over' ? '' : ' by $reason';
  if (r.winner == null) return 'Draw$by';
  return r.winner == r.playerSide ? 'You won$by' : 'You lost$by';
}

/// "1 Nov 2026, 09:05" in local time.
String formatMatchDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day} ${months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}
