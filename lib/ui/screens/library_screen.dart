import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/lessons_data.dart';
import '../../services/settings.dart';
import '../layout.dart';
import '../widgets/segmented_list.dart';
import 'topic_screen.dart';

/// Browse or type any chess concept and have the coach teach it.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _teach(String topic) {
    final t = topic.trim();
    if (t.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TopicScreen(topic: t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasKey = context.watch<SettingsController>().hasApiKey;
    return Scaffold(
      appBar: AppBar(title: const Text('Concept Library')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: withSystemInsets(context, const EdgeInsets.fromLTRB(16, 8, 16, 16)),
            children: [
              SearchBar(
                controller: _search,
                hintText: 'Show me on the board… (e.g. "the Greek gift sacrifice")',
                textInputAction: TextInputAction.search,
                onSubmitted: _teach,
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(segmentColor(scheme)),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
                leading: const Icon(Icons.search_rounded),
                trailing: [
                  IconButton(
                    tooltip: 'Teach me',
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () => _teach(_search.text),
                  ),
                ],
              ),
              if (!hasKey)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    'The library is powered by your AI coach. Add a Grok or Claude API key in Settings to use it.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const SegmentHeader('Topics'),
              SegmentedList(
                children: [
                  for (final entry in conceptLibrary.entries)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: text.titleMedium),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final topic in entry.value)
                                ActionChip(
                                  label: Text(topic),
                                  shape: const StadiumBorder(),
                                  onPressed: () => _teach(topic),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
