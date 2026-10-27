import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/coach_service.dart';
import '../../engine/engine_service.dart';
import '../../models/lesson.dart';
import '../../services/settings.dart';
import '../../state/lesson_controller.dart';
import '../../voice/voice_service.dart';
import '../layout.dart';
import '../widgets/voice_button.dart';
import '../widgets/board_view.dart';
import '../widgets/coach_feed.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late final LessonController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = LessonController(
      lesson: widget.lesson,
      engine: context.read<EngineService>(),
      coach: context.read<CoachService>(),
      settings: context.read<SettingsController>(),
      voice: context.read<VoiceService>(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.lesson.title),
            actions: [
              const VoiceButton(),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    'Step ${_ctrl.stepIndex + 1} / ${widget.lesson.steps.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (isWideLayout(constraints)) {
                  final size = sideBySideBoardSize(
                    constraints,
                    widthFraction: 0.5,
                    reserve: 32,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _board(size),
                      ),
                      Expanded(child: _panel(context)),
                    ],
                  );
                }
                final size = stackedBoardSize(
                  constraints,
                  heightFraction: 0.46,
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: _board(size),
                    ),
                    Expanded(child: _panel(context, compact: true)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _board(double size) => BoardView(
    position: _ctrl.position,
    lastMove: _ctrl.lastMove,
    size: size,
    orientation: _ctrl.studentSide,
    interactiveSide: _ctrl.canMove ? _ctrl.studentSide : null,
    shapes: _ctrl.shapes,
    onMove: _ctrl.onMove,
  );

  Widget _panel(BuildContext context, {bool compact = false}) {
    final step = _ctrl.step;
    final scheme = Theme.of(context).colorScheme;
    final solved = _ctrl.status == StepStatus.solved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          flex: compact ? 3 : 2,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 4,
              compact ? 2 : 16,
              compact ? 12 : 16,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (solved)
                      Chip(
                        avatar: Icon(
                          Icons.check_circle_rounded,
                          color: scheme.primary,
                          size: 18,
                        ),
                        label: const Text('Done'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  step.text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 6),
                _goalLine(context, step),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _ctrl.canMove ? _ctrl.requestHint : null,
                      icon: const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Hint'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ctrl.explainMore,
                      icon: const Icon(Icons.school_outlined, size: 18),
                      label: const Text('Explain more'),
                    ),
                    OutlinedButton.icon(
                      onPressed: step.goal == GoalType.read
                          ? null
                          : _ctrl.restartStep,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Reset'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ctrl.stepIndex > 0
                          ? _ctrl.previousStep
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      label: const Text('Back'),
                    ),
                    if (_ctrl.isLastStep)
                      FilledButton.icon(
                        onPressed: solved ? () => Navigator.pop(context) : null,
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Finish lesson'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: solved ? _ctrl.nextStep : null,
                        icon: const Icon(Icons.chevron_right_rounded, size: 18),
                        label: const Text('Next'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Flexible(
          flex: compact ? 2 : 3,
          child: CoachFeed(
            messages: _ctrl.messages,
            onAsk: _ctrl.ask,
            hint: 'Ask the coach about this lesson…',
          ),
        ),
      ],
    );
  }

  Widget _goalLine(BuildContext context, LessonStep step) {
    final scheme = Theme.of(context).colorScheme;
    final text = switch (step.goal) {
      GoalType.read => 'Read, then press Next.',
      GoalType.playLine =>
        step.line.length == 1
            ? 'Goal: find the one right move.'
            : 'Goal: play the ${(step.line.length + 1) ~/ 2}-move line. Wrong moves are rejected with a hint.',
      GoalType.reachSquare =>
        'Goal: reach ${step.targetSquare!.name} in ${step.maxMoves} move${step.maxMoves == 1 ? '' : 's'}.',
      GoalType.captureAll =>
        'Goal: capture every black pawn within ${step.maxMoves} moves (${_ctrl.movesUsed} used).',
      GoalType.checkmate =>
        step.maxMoves == 1
            ? 'Goal: checkmate in one move.'
            : 'Goal: checkmate within ${step.maxMoves} moves (${_ctrl.movesUsed} used). The engine defends.',
      GoalType.promote =>
        'Goal: promote the pawn within ${step.maxMoves} moves (${_ctrl.movesUsed} used).',
      GoalType.anyMove => 'Goal: play any legal move.',
    };
    return Row(
      children: [
        Icon(Icons.flag_outlined, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
