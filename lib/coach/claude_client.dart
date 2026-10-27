import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'llm_client.dart';

/// Minimal streaming client for the Claude Messages API.
///
/// There is no official Dart SDK, so this talks to `POST /v1/messages`
/// directly and parses the server-sent event stream.
class ClaudeClient implements LlmClient {
  ClaudeClient({
    required this.apiKey,
    required this.model,
    required this.effort,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static final Uri _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  final String apiKey;
  final String model;
  final String effort;
  final http.Client _http;

  bool get _supportsEffort => !model.startsWith('claude-haiku');
  bool get _supportsFallbacks => model == 'claude-opus-5' || model.startsWith('claude-fable');

  /// Streams the text of a single assistant turn.
  @override
  Stream<String> streamText({
    required String system,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 2048,
  }) async* {
    if (apiKey.isEmpty) {
      throw LlmException('No Claude API key set. Add one in Settings to enable the AI coach.');
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'stream': true,
      'system': system,
      'messages': messages,
      if (_supportsEffort) 'output_config': {'effort': effort},
      // Opus 5 safety classifiers can decline a request; "default" fallbacks
      // re-run it on Anthropic's recommended substitute server-side.
      if (_supportsFallbacks) 'fallbacks': 'default',
    };

    final request = http.Request('POST', _endpoint)
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (_supportsFallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
        if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
      })
      ..body = jsonEncode(body);

    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw LlmException('The coach took too long to respond. Try again.');
    } on http.ClientException catch (e) {
      throw LlmException('Network error reaching Claude: ${e.message}');
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      String message;
      try {
        final json = jsonDecode(text) as Map<String, dynamic>;
        message = (json['error'] as Map<String, dynamic>?)?['message'] as String? ?? text;
      } catch (_) {
        message = text;
      }
      throw LlmException('Claude API error ${response.statusCode}: $message',
          statusCode: response.statusCode);
    }

    String? stopReason;
    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      final Map<String, dynamic> event;
      try {
        event = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (event['type']) {
        case 'content_block_delta':
          final delta = event['delta'] as Map<String, dynamic>;
          if (delta['type'] == 'text_delta') yield delta['text'] as String;
        case 'message_delta':
          stopReason = (event['delta'] as Map<String, dynamic>?)?['stop_reason'] as String?;
        case 'error':
          final err = event['error'] as Map<String, dynamic>?;
          throw LlmException('Claude stream error: ${err?['message'] ?? payload}');
      }
    }

    if (stopReason == 'refusal') {
      throw LlmException('The coach declined to answer this request.');
    }
  }

  /// Convenience wrapper that collects the whole response.
  Future<String> complete({
    required String system,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 2048,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in streamText(system: system, messages: messages, maxTokens: maxTokens)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }
}
