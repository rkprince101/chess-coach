import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

/// Streaming client for OpenAI-style `/chat/completions` endpoints.
///
/// Used for Grok (xAI, `https://api.x.ai/v1`) and any other compatible
/// server (OpenAI, Ollama, LM Studio, OpenRouter…).
class OpenAiCompatibleClient implements LlmClient {
  OpenAiCompatibleClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.providerName,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final String providerName;
  final http.Client _http;

  Uri get _chatEndpoint => Uri.parse('${_trim(baseUrl)}/chat/completions');
  Uri get _modelsEndpoint => Uri.parse('${_trim(baseUrl)}/models');

  static String _trim(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  @override
  Stream<String> streamText({
    required String system,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 2048,
  }) async* {
    if (apiKey.isEmpty) {
      throw LlmException('No $providerName API key set. Add one in Settings to enable the AI coach.');
    }
    if (model.trim().isEmpty) {
      throw LlmException('No $providerName model selected. Pick one in Settings.');
    }

    final body = <String, dynamic>{
      'model': model,
      'stream': true,
      'max_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': system},
        ...messages,
      ],
    };

    final request = http.Request('POST', _chatEndpoint)
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
      })
      ..body = jsonEncode(body);

    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw LlmException('$providerName took too long to respond. Try again.');
    } on http.ClientException catch (e) {
      throw LlmException('Network error reaching $providerName: ${e.message}');
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      String message;
      try {
        final json = jsonDecode(text) as Map<String, dynamic>;
        final err = json['error'];
        message = err is Map ? (err['message']?.toString() ?? text) : (err?.toString() ?? text);
      } catch (_) {
        message = text;
      }
      throw LlmException('$providerName API error ${response.statusCode}: $message',
          statusCode: response.statusCode);
    }

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      final Map<String, dynamic> event;
      try {
        event = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (event['error'] != null) {
        final err = event['error'];
        throw LlmException('$providerName stream error: ${err is Map ? err['message'] : err}');
      }
      final choices = event['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>?;
      final content = delta?['content'];
      if (content is String && content.isNotEmpty) yield content;
    }
  }

  /// Lists model ids offered by the server (`GET /models`).
  Future<List<String>> listModels() async {
    if (apiKey.isEmpty) throw LlmException('Enter the $providerName API key first.');
    final http.Response response;
    try {
      response = await _http.get(_modelsEndpoint, headers: {'authorization': 'Bearer $apiKey'}).timeout(
            const Duration(seconds: 20),
          );
    } on TimeoutException {
      throw LlmException('$providerName did not answer in time.');
    } on http.ClientException catch (e) {
      throw LlmException('Network error reaching $providerName: ${e.message}');
    }
    if (response.statusCode != 200) {
      throw LlmException('$providerName API error ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body);
    final data = json is Map ? json['data'] : json;
    if (data is! List) return const [];
    final ids = <String>[
      for (final m in data)
        if (m is Map && m['id'] is String) m['id'] as String,
    ]..sort();
    return ids;
  }
}
