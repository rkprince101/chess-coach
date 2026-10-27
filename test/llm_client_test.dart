import 'dart:convert';

import 'package:chess/coach/claude_client.dart';
import 'package:chess/coach/llm_client.dart';
import 'package:chess/coach/openai_compat_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client sse(List<String> events, {int status = 200, void Function(http.BaseRequest)? onRequest}) {
  return MockClient.streaming((request, bodyStream) async {
    onRequest?.call(request);
    final body = events.join('\n');
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status,
        headers: {'content-type': 'text/event-stream'});
  });
}

void main() {
  group('OpenAiCompatibleClient', () {
    test('parses chat completion deltas and stops at [DONE]', () async {
      http.BaseRequest? seen;
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://api.x.ai/v1/',
        apiKey: 'k',
        model: 'grok-4',
        providerName: 'Grok',
        httpClient: sse([
          'data: {"choices":[{"delta":{"role":"assistant","content":""}}]}',
          'data: {"choices":[{"delta":{"content":"Hel"}}]}',
          'data: {"choices":[{"delta":{"content":"lo"}}]}',
          'data: [DONE]',
        ], onRequest: (r) => seen = r),
      );
      final text = await client
          .streamText(system: 'sys', messages: [
            {'role': 'user', 'content': 'hi'}
          ])
          .join();
      expect(text, 'Hello');
      expect(seen!.url.toString(), 'https://api.x.ai/v1/chat/completions');
      expect(seen!.headers['authorization'], 'Bearer k');
      final body = jsonDecode((seen as http.Request).body) as Map<String, dynamic>;
      expect(body['model'], 'grok-4');
      expect((body['messages'] as List).first, {'role': 'system', 'content': 'sys'});
      expect(body['stream'], isTrue);
    });

    test('surfaces API errors with the server message', () async {
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://api.x.ai/v1',
        apiKey: 'k',
        model: 'nope',
        providerName: 'Grok',
        httpClient: sse(['{"error":{"message":"model nope not found"}}'], status: 404),
      );
      expect(
        () => client.streamText(system: 's', messages: const []).join(),
        throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('model nope not found'))),
      );
    });

    test('refuses to call without a key', () {
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://api.x.ai/v1',
        apiKey: '',
        model: 'grok-4',
        providerName: 'Grok',
      );
      expect(() => client.streamText(system: 's', messages: const []).join(), throwsA(isA<LlmException>()));
    });
  });

  group('ClaudeClient', () {
    test('parses text deltas and sends Opus 5 fallbacks header', () async {
      http.BaseRequest? seen;
      final client = ClaudeClient(
        apiKey: 'k',
        model: 'claude-opus-5',
        effort: 'medium',
        httpClient: sse([
          'event: message_start',
          'data: {"type":"message_start","message":{}}',
          'event: content_block_delta',
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Good "}}',
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"move"}}',
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}',
          'data: {"type":"message_stop"}',
        ], onRequest: (r) => seen = r),
      );
      final text = await client.streamText(system: 'sys', messages: const []).join();
      expect(text, 'Good move');
      expect(seen!.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      final body = jsonDecode((seen as http.Request).body) as Map<String, dynamic>;
      expect(body['fallbacks'], 'default');
      expect(body['output_config'], {'effort': 'medium'});
    });

    test('reports refusals', () async {
      final client = ClaudeClient(
        apiKey: 'k',
        model: 'claude-opus-5',
        effort: 'low',
        httpClient: sse([
          'data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}',
        ]),
      );
      expect(() => client.streamText(system: 's', messages: const []).join(),
          throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('declined'))));
    });
  });
}
