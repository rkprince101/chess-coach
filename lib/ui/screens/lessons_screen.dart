import 'package:flutter/material.dart';

import '../../data/lessons_data.dart';
import '../../models/lesson.dart';
import '../layout.dart';
import 'lesson_screen.dart';

class LessonsScreen extends StatelessWidget {
  const LessonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lessons')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: withSystemInsets(context, const EdgeInsets.all(16)),
            children: [
              for (final category in LessonCategory.values) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
                      Text(category.subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
                    ],
                  ),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, lesson) in lessons.where((l) => l.category == category).indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          title: Text(lesson.title),
                          subtitle: Text(lesson.summary),
                          trailing: Text('${lesson.steps.length} step${lesson.steps.length == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline)),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(builder: (_) => LessonScreen(lesson: lesson)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
