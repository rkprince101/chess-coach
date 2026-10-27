class LlmException implements Exception {
  LlmException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// A streaming chat completion backend. Messages use the shared
/// `{'role': 'user' | 'assistant', 'content': String}` shape.
abstract class LlmClient {
  Stream<String> streamText({
    required String system,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 2048,
  });
}
