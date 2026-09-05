import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'openai_device_auth.dart';
import 'openai_sse.dart';
import 'session_brief.dart';

const _kClientVersion = '0.144.6';
const _kModels = ['gpt-5.4', 'gpt-4.1', 'gpt-4o'];

const _kInstructions =
    'You are Verity Coach inside a personal Polar Verity Sense Android app. '
    'You are not a medical device and must not diagnose, prescribe, or claim '
    'clinical certainty. Speak plainly. Use only numbers in the session brief. '
    'If PPG, motion, or HRV beats are missing, say so and explain that a longer '
    'HR-only take can be much smaller than a shorter PPG take because nothing '
    'is compressed. Recommend recovery habits, not treatment. Never ask the '
    'user to paste raw SQLite or upload health files to GitHub.';

class ChatTurn {
  final String role;
  final String text;
  const ChatTurn({required this.role, required this.text});
}

class OpenAiChatService {
  final OpenAiDeviceAuth auth;
  final http.Client _http;
  final String _sessionId = const Uuid().v4();

  OpenAiChatService({OpenAiDeviceAuth? auth, http.Client? httpClient})
      : auth = auth ?? OpenAiDeviceAuth(),
        _http = httpClient ?? http.Client();

  Future<String> ask({
    required String question,
    required List<ChatTurn> history,
    String? focusSessionId,
  }) async {
    final session = await auth.ensureFreshSession();
    final brief = await SessionBrief.build(focusSessionId: focusSessionId);
    final input = <Map<String, dynamic>>[
      _textMessage(
        'system',
        'Session brief (local phone data, compact — not raw PPG):\n$brief',
      ),
      for (final turn in history.take(12)) _textMessage(turn.role, turn.text),
      _textMessage('user', question),
    ];

    Object? lastError;
    for (final model in _kModels) {
      try {
        return await _complete(
          session: session,
          model: model,
          input: input,
        );
      } catch (e) {
        lastError = e;
        final msg = e.toString().toLowerCase();
        if (msg.contains('model') || msg.contains('unsupported') || msg.contains('400')) {
          continue;
        }
        rethrow;
      }
    }
    throw Exception('ChatGPT request failed: $lastError');
  }

  Future<String> _complete({
    required OpenAiSession session,
    required String model,
    required List<Map<String, dynamic>> input,
  }) async {
    final uri = Uri.parse(
      'https://chatgpt.com/backend-api/codex/responses?client_version=$_kClientVersion',
    );
    final request = http.Request('POST', uri);
    request.headers.addAll({
      'Authorization': 'Bearer ${session.accessToken}',
      if (session.accountId != null) 'chatgpt-account-id': session.accountId!,
      'OpenAI-Beta': 'responses=experimental',
      'originator': 'codex_cli_rs',
      'Content-Type': 'application/json',
      'session_id': _sessionId,
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'model': model,
      'instructions': _kInstructions,
      'input': input,
      'store': false,
      'stream': true,
      'parallel_tool_calls': false,
    });

    final streamed = await _http.send(request);
    if (streamed.statusCode == 401) {
      final fresh = await auth.refresh(session);
      return _complete(session: fresh, model: model, input: input);
    }
    if (streamed.statusCode != 200) {
      await streamed.stream.drain<void>();
      throw Exception('ChatGPT HTTP ${streamed.statusCode}');
    }
    final collector = SseTextCollector();
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      collector.addChunk(chunk);
    }
    collector.finish();
    final text = collector.text.trim();
    if (text.isEmpty) {
      throw Exception('ChatGPT returned an empty answer. Try again.');
    }
    return text;
  }

  static Map<String, dynamic> _textMessage(String role, String text) {
    return {
      'type': 'message',
      'role': role,
      'content': [
        {'type': 'input_text', 'text': text},
      ],
    };
  }
}
