import 'package:flutter/material.dart';

import '../../state/game_controller.dart' show CoachMessage, CoachMessageKind;

/// Scrolling feed of coach messages with an input box for questions.
class CoachFeed extends StatefulWidget {
  const CoachFeed({
    super.key,
    required this.messages,
    required this.onAsk,
    this.hint = 'Ask the coach anything about this position…',
    this.enabled = true,
  });

  final List<CoachMessage> messages;
  final Future<void> Function(String question) onAsk;
  final String hint;
  final bool enabled;

  @override
  State<CoachFeed> createState() => _CoachFeedState();
}

class _CoachFeedState extends State<CoachFeed> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  int _lastCount = 0;
  int _lastLength = 0;

  @override
  void didUpdateWidget(covariant CoachFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final total = widget.messages.fold<int>(0, (n, m) => n + m.text.length);
    if (widget.messages.length != _lastCount || total != _lastLength) {
      _lastCount = widget.messages.length;
      _lastLength = total;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    widget.onAsk(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: widget.messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_outlined, size: 32, color: scheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        'Coach will comment here',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, i) => _MessageBubble(message: widget.messages[i]),
                ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: scheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: scheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: scheme.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: widget.enabled ? _send : null,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                child: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (message.kind) {
      CoachMessageKind.coach => (Icons.school_rounded, scheme.primary, 'Coach'),
      CoachMessageKind.tip => (Icons.lightbulb_outline_rounded, const Color(0xFFF9A825), 'Tip'),
      CoachMessageKind.warning => (Icons.warning_amber_rounded, const Color(0xFFEF6C00), 'Heads up'),
      CoachMessageKind.praise => (Icons.thumb_up_alt_outlined, const Color(0xFF2E7D32), 'Nice'),
      CoachMessageKind.user => (Icons.person_outline_rounded, scheme.secondary, 'You'),
      CoachMessageKind.error => (Icons.error_outline_rounded, scheme.error, 'Problem'),
      CoachMessageKind.system => (Icons.info_outline_rounded, scheme.outline, 'Game'),
    };
    final isUser = message.kind == CoachMessageKind.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? scheme.secondaryContainer.withValues(alpha: 0.6)
                    : color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
                      if (message.streaming) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    message.text.isEmpty && message.streaming ? 'Thinking…' : message.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
