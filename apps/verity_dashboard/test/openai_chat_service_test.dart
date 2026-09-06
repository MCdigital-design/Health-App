import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/ai/openai_chat_service.dart';

void main() {
  test('Codex body matches the ChatGPT backend allowlist', () {
    final body = buildCodexChatBody(
      model: 'gpt-5.6-terra',
      instructions: 'You are Verity Coach.\n\nSession brief: HR 1540 PPG 0',
      history: const [
        ChatTurn(role: 'user', text: 'hi'),
        ChatTurn(role: 'assistant', text: 'hello'),
        ChatTurn(role: 'system', text: 'must not appear'),
      ],
      question: 'what data can you see',
    );

    expect(body.keys.toSet(), {'model', 'stream', 'store', 'instructions', 'input'});
    expect(body['stream'], isTrue);
    expect(body['store'], isFalse);
    expect(body.containsKey('parallel_tool_calls'), isFalse);
    expect(body['instructions'], contains('Session brief'));

    final input = body['input'] as List;
    expect(input, hasLength(3));
    expect(input.every((item) => item['type'] == null), isTrue);
    expect(input.every((item) => item['role'] != 'system'), isTrue);
    expect(input.last['role'], 'user');
    expect(input.last['content'][0]['type'], 'input_text');
    expect(input.last['content'][0]['text'], 'what data can you see');
  });

  test('friendlyChatGptError surfaces detail without dumping the body', () {
    expect(
      friendlyChatGptError(400, '{"detail":"Unsupported parameter: parallel_tool_calls"}'),
      'ChatGPT: Unsupported parameter: parallel_tool_calls',
    );
    expect(friendlyChatGptError(400, '<html>cloudflare</html>'), 'ChatGPT HTTP 400');
  });
}
