import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/openai_compat_client.dart';
import '../../services/settings.dart';
import '../layout.dart';
import '../widgets/segmented_list.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<CoachProvider, TextEditingController> _keyCtrls = {};
  final Map<CoachProvider, TextEditingController> _modelCtrls = {};
  late final TextEditingController _customUrl;
  bool _showKey = false;
  bool _fetchingModels = false;
  List<String> _fetchedModels = const [];
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsController>();
    for (final p in CoachProvider.values) {
      _keyCtrls[p] = TextEditingController(text: s.keyFor(p));
      _modelCtrls[p] = TextEditingController(text: s.modelFor(p));
    }
    _customUrl = TextEditingController(text: s.customBaseUrl);
  }

  @override
  void dispose() {
    for (final c in [..._keyCtrls.values, ..._modelCtrls.values, _customUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchModels(SettingsController s) async {
    setState(() {
      _fetchingModels = true;
      _fetchError = null;
    });
    final client = OpenAiCompatibleClient(
      baseUrl: s.baseUrl,
      apiKey: s.apiKey,
      model: s.model,
      providerName: s.provider.label,
    );
    try {
      final models = await client.listModels();
      if (!mounted) return;
      setState(() {
        _fetchedModels = models;
        if (models.isEmpty) _fetchError = 'The server returned no models.';
      });
    } catch (e) {
      if (mounted) setState(() => _fetchError = e.toString());
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  static const _rowPadding = EdgeInsets.fromLTRB(20, 16, 20, 16);
  static const _tilePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 4);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final note = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: withSystemInsets(context, const EdgeInsets.fromLTRB(16, 0, 16, 16)),
            children: [
              const SegmentHeader('Coach'),
              SegmentedList(
                children: [
                  SwitchListTile(
                    contentPadding: _tilePadding,
                    value: s.coachEnabled,
                    title: const Text('Enable coach'),
                    subtitle: const Text('Show coach tips, explanations, and feedback during play'),
                    onChanged: s.setCoachEnabled,
                  ),
                  if (s.coachEnabled)
                    SwitchListTile(
                      contentPadding: _tilePadding,
                      value: s.showCoachDetails,
                      title: const Text('Show coach panel'),
                      subtitle: const Text('Display coach feed, move list, and coaching prompts in Play & Learn'),
                      onChanged: s.setShowCoachDetails,
                    ),
                ],
              ),
              if (s.coachEnabled) ...[
                const SegmentHeader('AI coach'),
                SegmentedList(
                  children: [
                    Padding(
                      padding: _rowPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<CoachProvider>(
                            segments: [
                              for (final p in CoachProvider.values)
                                ButtonSegment(value: p, label: Text(p.label, textAlign: TextAlign.center)),
                            ],
                            selected: {s.provider},
                            showSelectedIcon: false,
                            onSelectionChanged: (v) {
                              setState(() {
                                _fetchedModels = const [];
                                _fetchError = null;
                              });
                              s.setProvider(v.first);
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(s.provider.help, style: note),
                        ],
                      ),
                    ),
                    Padding(
                      padding: _rowPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ..._providerFields(context, s),
                          const SizedBox(height: 8),
                          Text('Keys are stored only on this device and sent only to the provider you selected.',
                              style: note),
                        ],
                      ),
                    ),
                  ],
                ),
                const SegmentHeader('Coaching style'),
                SegmentedList(
                  children: [
                    for (final mode in CoachMode.values)
                      RadioListTile<CoachMode>(
                        contentPadding: _tilePadding,
                        value: mode,
                        groupValue: s.coachMode,
                        title: Text(mode.label),
                        subtitle: Text(mode.description),
                        onChanged: (v) => v == null ? null : s.setCoachMode(v),
                      ),
                  ],
                ),
                const SegmentHeader('Explanations'),
                SegmentedList(
                  children: [
                    Padding(
                      padding: _rowPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<PlayerLevel>(
                            initialValue: s.playerLevel,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'My level',
                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                            ),
                            items: [
                              for (final l in PlayerLevel.values)
                                DropdownMenuItem(
                                  value: l,
                                  child: Text('${l.label} — ${l.description}', overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) => v == null ? null : s.setPlayerLevel(v),
                          ),
                          const SizedBox(height: 8),
                          Text('Beginner: the coach avoids chess notation and describes moves in words.', style: note),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: _tilePadding,
                      value: s.autoPreview,
                      title: const Text('Replay the consequences on the board'),
                      subtitle: const Text(
                          'When a move is flagged, the pieces move to show how the opponent would punish it.'),
                      onChanged: s.setAutoPreview,
                    ),
                    SwitchListTile(
                      contentPadding: _tilePadding,
                      value: s.revealBestMove,
                      title: const Text('Reveal the best move in explanations'),
                      subtitle: const Text(
                          'Off: the coach hints and lets you find it. On: the coach names the better move.'),
                      onChanged: s.setRevealBestMove,
                    ),
                  ],
                ),
              ],
              const SegmentHeader('Difficulty'),
              SegmentedList(
                children: [
                  Padding(
                    padding: _rowPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Elo rating', style: text.titleMedium),
                            FilledButton.tonal(
                              onPressed: null,
                              child: Text('${s.eloRating} • ${s.eloLabel}'),
                            ),
                          ],
                        ),
                        Slider(
                          value: s.eloRating.toDouble(),
                          min: 400,
                          max: 2000,
                          divisions: 32,
                          label: '${s.eloRating} (${s.eloLabel})',
                          onChanged: (v) => s.setEloRating(v.round()),
                        ),
                        Text(
                            'Like Duolingo, Elo adjusts opponent strength to match your level. Lower Elo = easier opponent.',
                            style: note),
                      ],
                    ),
                  ),
                  Padding(
                    padding: _rowPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Engine skill level: ${s.engineLevel} / 8', style: text.titleMedium),
                        Text('Advanced: manual override of engine strength', style: note),
                        Slider(
                          value: s.engineLevel.toDouble(),
                          min: 1,
                          max: 8,
                          divisions: 7,
                          label: '${s.engineLevel}',
                          onChanged: (v) => s.setEngineLevel(v.round()),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: _rowPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Thinking time: ${(s.thinkTimeMs / 1000).toStringAsFixed(1)} s', style: text.titleMedium),
                        Slider(
                          value: s.thinkTimeMs.toDouble(),
                          min: 300,
                          max: 3000,
                          divisions: 9,
                          label: '${(s.thinkTimeMs / 1000).toStringAsFixed(1)} s',
                          onChanged: (v) => s.setThinkTimeMs(v.round()),
                        ),
                        Text('Longer thinking makes both the opponent and the move grading stronger.', style: note),
                      ],
                    ),
                  ),
                ],
              ),
              const SegmentHeader('Appearance'),
              SegmentedList(
                children: [
                  Padding(
                    padding: _rowPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Theme color', style: text.titleMedium),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in [
                              const Color(0xFF6750A4),
                              const Color(0xFF006A6A),
                              const Color(0xFF386A20),
                              const Color(0xFF7C5800),
                              const Color(0xFFBA1A1A),
                              const Color(0xFF8C4190),
                            ])
                              GestureDetector(
                                onTap: () => s.setThemeSeedColor(c.toARGB32()),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: s.themeSeedColor == c.toARGB32() ? scheme.primary : scheme.outlineVariant,
                                      width: s.themeSeedColor == c.toARGB32() ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Follows system theme with selected color', style: note),
                      ],
                    ),
                  ),
                ],
              ),
              const SegmentHeader('Board'),
              SegmentedList(
                children: [
                  SwitchListTile(
                    contentPadding: _tilePadding,
                    value: s.playAsWhite,
                    title: const Text('Play as White by default'),
                    onChanged: s.setPlayAsWhite,
                  ),
                  SwitchListTile(
                    contentPadding: _tilePadding,
                    value: s.showEvalBar,
                    title: const Text('Show evaluation bar'),
                    onChanged: s.setShowEvalBar,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _providerFields(BuildContext context, SettingsController s) {
    final p = s.provider;
    final scheme = Theme.of(context).colorScheme;
    final keyField = TextField(
      controller: _keyCtrls[p],
      obscureText: !_showKey,
      decoration: InputDecoration(
        labelText: '${p.label} API key',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _showKey = !_showKey),
        ),
      ),
      onChanged: (v) => s.setKey(p, v),
    );

    if (p == CoachProvider.claude) {
      return [
        keyField,
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: SettingsController.claudeModels.contains(s.model) ? s.model : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
          items: [
            for (final m in SettingsController.claudeModels)
              DropdownMenuItem(
                value: m,
                child: Text(switch (m) {
                  'claude-opus-5' => 'Claude Opus 5 (best explanations)',
                  'claude-sonnet-5' => 'Claude Sonnet 5 (fast, cheaper)',
                  _ => 'Claude Haiku 4.5 (fastest)',
                }),
              ),
          ],
          onChanged: (v) => v == null ? null : s.setModel(p, v),
        ),
        const SizedBox(height: 12),
        Text('Thinking effort', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'low', label: Text('Low'), icon: Icon(Icons.bolt_rounded)),
            ButtonSegment(value: 'medium', label: Text('Medium')),
            ButtonSegment(value: 'high', label: Text('High'), icon: Icon(Icons.psychology_outlined)),
          ],
          selected: {s.effort},
          onSelectionChanged: (v) => s.setEffort(v.first),
        ),
        const SizedBox(height: 4),
        Text('Higher effort gives deeper explanations but takes longer per reply.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
      ];
    }

    return [
      if (p == CoachProvider.custom) ...[
        TextField(
          controller: _customUrl,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            helperText: 'e.g. https://api.openai.com/v1 or http://localhost:11434/v1',
            border: OutlineInputBorder(),
          ),
          onChanged: s.setCustomBaseUrl,
        ),
        const SizedBox(height: 12),
      ],
      keyField,
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _modelCtrls[p],
              decoration: InputDecoration(
                labelText: 'Model',
                helperText: p.defaultModel.isEmpty ? 'Model id as the server names it' : 'e.g. ${p.defaultModel}',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => s.setModel(p, v),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton.tonalIcon(
              onPressed: _fetchingModels ? null : () => _fetchModels(s),
              icon: _fetchingModels
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded, size: 18),
              label: const Text('Fetch models'),
            ),
          ),
        ],
      ),
      if (_fetchError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_fetchError!, style: TextStyle(color: scheme.error)),
        ),
      if (_fetchedModels.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _fetchedModels)
                ChoiceChip(
                  label: Text(m),
                  selected: s.model == m,
                  onSelected: (_) {
                    _modelCtrls[p]!.text = m;
                    s.setModel(p, m);
                  },
                ),
            ],
          ),
        ),
    ];
  }
}
