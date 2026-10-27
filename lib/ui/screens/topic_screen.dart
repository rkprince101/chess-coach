import 'package:chessground/chessground.dart' show Arrow, Shape;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/coach_service.dart';
import '../../coach/demo_builder.dart';
import '../../coach/facts.dart';
import '../../models/lesson.dart';
import '../../voice/voice_service.dart';
import '../layout.dart';
import '../widgets/board_view.dart';
import '../widgets/voice_button.dart';
import 'lesson_screen.dart';

/// Teaches one concept on the board: the coach builds a verified demo
/// (positions, moves, arrows, captions) that the student walks through, can
/// try themselves, and can ask follow-up questions about.
class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key, required this.topic});

  final String topic;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  BoardDemo? _demo;
  bool _loading = true;
  String _status = 'Asking the coach to set up the board…';
  String? _error;

  // Text fallback when no legal board demo could be built.
  final _fallbackText = StringBuffer();
  bool _fallbackStreaming = false;

  int _stepIndex = 0;
  int _moveIndex = 0;
  bool _tryMode = false;
  int _tryAttempts = 0;
  String? _tryFeedback;

  final _followUp = TextEditingController();
  final List<(String q, String a)> _thread = [];
  bool _answering = false;

  late final List<Lesson> _practice = matchingLessons(widget.topic);
  late final VoiceService _voice = context.read<VoiceService>();

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void dispose() {
    _voice.stop();
    _followUp.dispose();
    super.dispose();
  }

  void _speak(String text, {bool interrupt = false}) {
    if (_voice.enabled) _voice.say(text, interrupt: interrupt);
  }

  Future<void> _build() async {
    setState(() {
      _loading = true;
      _error = null;
      _demo = null;
      _stepIndex = 0;
      _moveIndex = 0;
      _tryMode = false;
    });
    final coach = context.read<CoachService>();
    try {
      final demo = await coach.buildDemo(
        widget.topic,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      setState(() => _demo = demo);
      if (demo != null && demo.steps.isNotEmpty) {
        _speak('${demo.intro} ${demo.steps.first.title}. ${demo.steps.first.text}', interrupt: true);
      }
      if (demo == null || demo.steps.isEmpty) await _streamFallback();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _streamFallback() async {
    if (_fallbackText.isNotEmpty) return;
    setState(() => _fallbackStreaming = true);
    final coach = context.read<CoachService>();
    try {
      await for (final chunk in coach.teachTopic(widget.topic)) {
        if (!mounted) return;
        setState(() => _fallbackText.write(chunk));
      }
      _speak(_fallbackText.toString(), interrupt: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _fallbackStreaming = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Walkthrough state

  DemoStep? get _step {
    final d = _demo;
    if (d == null || d.steps.isEmpty) return null;
    return d.steps[_stepIndex.clamp(0, d.steps.length - 1)];
  }

  Position? get _position => _step?.positions[_moveIndex];
  Move? get _lastMove => _moveIndex == 0 ? null : _step!.moves[_moveIndex - 1];

  Set<Shape> get _shapes {
    final step = _step;
    if (step == null) return const {};
    if (_moveIndex == 0) {
      return _tryMode && _tryAttempts < 2 ? const {} : step.shapes;
    }
    final m = _lastMove;
    if (m is NormalMove) {
      return {Arrow(color: const Color(0xCCE53935), orig: m.from, dest: m.to)};
    }
    return const {};
  }

  String? get _narration {
    final step = _step;
    if (step == null || _moveIndex == 0) return null;
    return friendlyMove(
      step.positions[_moveIndex - 1],
      step.moves[_moveIndex - 1],
    );
  }

  void _goStep(int index) {
    setState(() {
      _stepIndex = index;
      _moveIndex = 0;
      _tryMode = false;
      _tryAttempts = 0;
      _tryFeedback = null;
    });
    final step = _step;
    if (step != null) _speak('${step.title}. ${step.text}', interrupt: true);
  }

  void _nextMove() {
    final step = _step;
    if (step == null || _moveIndex >= step.moves.length) return;
    setState(() {
      _moveIndex++;
      _tryMode = false;
    });
    final narration = _narration;
    if (narration != null) {
      final finished = _moveIndex >= step.moves.length;
      final last = finished && _stepIndex == _demo!.steps.length - 1;
      _speak(
        [
          narration,
          if (finished && step.afterText != null) step.afterText!,
          if (last && _demo!.summary.isNotEmpty) 'Rule of thumb: ${_demo!.summary}',
        ].join('. '),
        interrupt: true,
      );
    }
  }

  void _prevMove() {
    if (_moveIndex == 0) return;
    setState(() => _moveIndex--);
  }

  void _toggleTry() {
    setState(() {
      _tryMode = !_tryMode;
      _moveIndex = 0;
      _tryAttempts = 0;
      _tryFeedback = _tryMode ? 'Your turn: find the move on the board.' : null;
    });
  }

  void _onTryMove(Move raw) {
    final step = _step;
    if (step == null || !_tryMode || step.moves.isEmpty) return;
    final pos = step.start;
    final move = raw is NormalMove ? pos.normalizeMove(raw) : raw;
    if (!pos.isLegal(move)) return;
    final expected = step.moves.first;
    if (move.uci == expected.uci) {
      setState(() {
        _tryFeedback = 'Yes! ${friendlyMove(pos, move)}.';
        _tryMode = false;
        _moveIndex = 1;
      });
      _speak(_tryFeedback!, interrupt: true);
      return;
    }
    _tryAttempts++;
    final piece = pos.board.pieceAt((expected as NormalMove).from);
    setState(() {
      _tryFeedback = _tryAttempts >= 2
          ? 'Not that one. Look at the ${piece == null ? 'highlighted' : roleName(piece.role)} on ${expected.from.name}; the arrows show the idea. Try once more or press "Next move" to see it.'
          : '${friendlyMove(pos, move)} is legal, but it is not the idea we are studying. Try again.';
    });
    _speak(_tryFeedback!, interrupt: true);
  }

  // ---------------------------------------------------------------------------
  // Follow-up questions

  Future<void> _ask() async {
    final q = _followUp.text.trim();
    if (q.isEmpty || _answering) return;
    _followUp.clear();
    setState(() {
      _answering = true;
      _thread.add((q, ''));
    });
    final coach = context.read<CoachService>();
    final demoText = _demoAsText();
    final history = <Map<String, dynamic>>[
      {'role': 'user', 'content': 'Teach me about: ${widget.topic}'},
      {'role': 'assistant', 'content': demoText},
      for (final (question, answer) in _thread.take(_thread.length - 1)) ...[
        {'role': 'user', 'content': question},
        {'role': 'assistant', 'content': answer},
      ],
    ];
    final pos = _position;
    final question = pos == null
        ? q
        : 'The board currently shows this position from the demo (FEN ${pos.fen}). Question: $q';
    try {
      final idx = _thread.length - 1;
      final answer = StringBuffer();
      await for (final chunk in coach.followUp(question, history)) {
        if (!mounted) return;
        answer.write(chunk);
        setState(() => _thread[idx] = (q, answer.toString()));
      }
      _speak(answer.toString(), interrupt: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  String _demoAsText() {
    final d = _demo;
    if (d == null) return _fallbackText.toString();
    final buffer = StringBuffer('${d.title}\n${d.intro}\n');
    for (final s in d.steps) {
      buffer.writeln(
        '${s.title}: ${s.text} (FEN ${s.start.fen}; moves ${lineToSan(s.start, s.moves)}) ${s.afterText ?? ''}',
      );
    }
    buffer.writeln(d.summary);
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    final demo = _demo;
    final hasBoard = demo != null && demo.steps.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          demo?.title.isNotEmpty == true ? demo!.title : widget.topic,
        ),
        actions: [
          const VoiceButton(),
          IconButton(
            tooltip: 'Build a fresh demo',
            onPressed: _loading ? null : _build,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && demo == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_status),
                  const SizedBox(height: 4),
                  Text(
                    'Every position is checked for legality before it reaches the board.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : hasBoard
          ? _boardLayout(context)
          : _textLayout(context),
    );
  }

  Widget _boardLayout(BuildContext context) {
    return SafeArea(
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
                Padding(padding: const EdgeInsets.all(16), child: _board(size)),
                Expanded(child: _panel(context)),
              ],
            );
          }
          final size = stackedBoardSize(constraints, heightFraction: 0.46);
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
    );
  }

  Widget _board(double size) {
    final step = _step!;
    return BoardView(
      position: _position!,
      lastMove: _lastMove,
      size: size,
      orientation: step.start.turn,
      interactiveSide: _tryMode ? step.start.turn : null,
      shapes: _shapes,
      onMove: _onTryMove,
    );
  }

  Widget _panel(BuildContext context, {bool compact = false}) {
    final demo = _demo!;
    final step = _step!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final movesDone = _moveIndex >= step.moves.length;
    final isLast = _stepIndex == demo.steps.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 4,
              compact ? 2 : 16,
              compact ? 12 : 16,
              8,
            ),
            children: [
              if (_stepIndex == 0 &&
                  _moveIndex == 0 &&
                  demo.intro.isNotEmpty) ...[
                Text(demo.intro, style: text.bodyMedium?.copyWith(height: 1.4)),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Step ${_stepIndex + 1} of ${demo.steps.length}: ${step.title}',
                      style: text.titleMedium,
                    ),
                  ),
                  if (step.moves.isNotEmpty)
                    Text(
                      'move $_moveIndex / ${step.moves.length}',
                      style: text.labelMedium,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(step.text, style: text.bodyMedium?.copyWith(height: 1.4)),
              if (_narration != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_moveIndex. $_narration',
                    style: text.bodyMedium,
                  ),
                ),
              ],
              if (movesDone &&
                  step.afterText != null &&
                  step.afterText!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  step.afterText!,
                  style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
              if (_tryFeedback != null) ...[
                const SizedBox(height: 8),
                Text(
                  _tryFeedback!,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (movesDone && isLast && demo.summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        color: scheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Rule of thumb: ${demo.summary}',
                          style: text.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _moveIndex > 0
                        ? _prevMove
                        : (_stepIndex > 0
                              ? () => _goStep(_stepIndex - 1)
                              : null),
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: Text(_moveIndex > 0 ? 'Undo move' : 'Previous step'),
                  ),
                  if (!movesDone)
                    FilledButton.icon(
                      onPressed: _nextMove,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Next move'),
                    ),
                  if (movesDone && !isLast)
                    FilledButton.icon(
                      onPressed: () => _goStep(_stepIndex + 1),
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      label: const Text('Next step'),
                    ),
                  if (step.moves.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: _toggleTry,
                      icon: Icon(
                        _tryMode
                            ? Icons.close_rounded
                            : Icons.touch_app_outlined,
                        size: 18,
                      ),
                      label: Text(_tryMode ? 'Stop trying' : 'Try it yourself'),
                    ),
                  if (_practice.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => LessonScreen(lesson: _practice.first),
                        ),
                      ),
                      icon: const Icon(Icons.school_outlined, size: 18),
                      label: Text('Practise: ${_practice.first.title}'),
                    ),
                ],
              ),
              if (demo.problems.isNotEmpty || step.truncated) ...[
                const SizedBox(height: 10),
                Text(
                  'Some positions or moves the coach suggested were illegal and were left out.',
                  style: text.bodySmall?.copyWith(color: scheme.outline),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              for (final (q, a) in _thread) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(q, style: text.titleSmall),
                ),
                const SizedBox(height: 6),
                if (a.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  SelectableText(
                    a,
                    style: text.bodyMedium?.copyWith(height: 1.4),
                  ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        _askBar(),
      ],
    );
  }

  Widget _textLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5);
    final demo = _demo;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card(
                      color: scheme.tertiaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.grid_off_rounded),
                        title: const Text('No board demo this time'),
                        subtitle: const Text(
                          'The coach could not produce legal positions for this topic, so here is the explanation in words. Try again for a new attempt.',
                        ),
                        trailing: TextButton(
                          onPressed: _loading ? null : _build,
                          child: const Text('Try again'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (demo != null && demo.intro.isNotEmpty) ...[
                      SelectableText(demo.intro, style: body),
                      const SizedBox(height: 12),
                    ],
                    if (_fallbackText.isEmpty && _fallbackStreaming)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      SelectableText(_fallbackText.toString(), style: body),
                    if (demo != null && demo.summary.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Rule of thumb: ${demo.summary}',
                        style: body?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (_practice.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    LessonScreen(lesson: _practice.first),
                              ),
                            ),
                            icon: const Icon(Icons.school_outlined, size: 18),
                            label: Text('Practise: ${_practice.first.title}'),
                          ),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    for (final (q, a) in _thread) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          q,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (a.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        SelectableText(a, style: body),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              _askBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _askBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _followUp,
              enabled: !_answering,
              onSubmitted: (_) => _ask(),
              decoration: const InputDecoration(
                hintText: 'Ask about this position or idea…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: _answering ? null : _ask,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
