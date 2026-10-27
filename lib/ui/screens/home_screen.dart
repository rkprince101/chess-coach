import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings.dart';
import '../layout.dart';
import '../widgets/segmented_list.dart';
import 'lessons_screen.dart';
import 'library_screen.dart';
import 'play_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Coach'),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: withSystemInsets(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Learn chess by playing',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Play games with AI coaching, interactive lessons, and tactical training tailored to your Elo rating.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (settings.coachEnabled && !settings.hasApiKey) ...[
                const SizedBox(height: 20),
                Card(
                  color: scheme.tertiaryContainer,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    leading: Icon(Icons.key_rounded, color: scheme.onTertiaryContainer),
                    title: Text('Add AI API key', style: TextStyle(color: scheme.onTertiaryContainer)),
                    subtitle: Text(
                      'Unlock detailed coaching explanations and Q&A',
                      style: TextStyle(color: scheme.onTertiaryContainer.withValues(alpha: 0.8)),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: scheme.onTertiaryContainer),
                    onTap: () => _open(context, const SettingsScreen()),
                  ),
                ),
              ],
              const SegmentHeader('Start learning'),
              SegmentedList(
                children: [
                  _ModeTile(
                    icon: Icons.sports_esports_rounded,
                    title: 'Play & Learn',
                    subtitle: 'Game vs opponent • Elo ${settings.eloRating} • ${settings.eloLabel}',
                    onTap: () => _open(context, const PlayScreen()),
                  ),
                  _ModeTile(
                    icon: Icons.menu_book_rounded,
                    title: 'Lessons',
                    subtitle: 'Interactive curriculum from basics to advanced',
                    onTap: () => _open(context, const LessonsScreen()),
                  ),
                  _ModeTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Concept Library',
                    subtitle: 'Tactics, patterns, and openings with demos',
                    onTap: () => _open(context, const LibraryScreen()),
                  ),
                  _ModeTile(
                    icon: Icons.tune_rounded,
                    title: 'Settings',
                    subtitle: 'Coach, difficulty, API keys, and preferences',
                    onTap: () => _open(context, const SettingsScreen()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }
}

/// One row of the "Start learning" group.
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: scheme.onPrimaryContainer, size: 24),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
