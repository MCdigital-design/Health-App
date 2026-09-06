import 'dart:convert';

import 'package:http/http.dart' as http;

import 'openai_device_auth.dart';
import 'openai_models.dart';
import 'openai_sse.dart';
import 'session_brief.dart';
import 'studio_spec.dart';

const kCodexResponsesUrl = 'https://chatgpt.com/backend-api/codex/responses';

const _kCoach =
    'You are Verity Coach inside a personal Polar Verity Sense Android app. '
    'You are not a medical device and must not diagnose, prescribe, or claim '
    'clinical certainty. Speak plainly. Use only numbers in the session brief. '
    'PPG and motion traces in the brief are min/max envelopes, not every sample — '
    'do not treat missing raw points as missing data, and do not invent values. '
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

  OpenAiChatService({OpenAiDeviceAuth? auth, http.Client? httpClient})
      : auth = auth ?? OpenAiDeviceAuth(),
        _http = httpClient ?? http.Client();

  Future<String> ask({
    required String question,
    required List<ChatTurn> history,
    String? focusSessionId,
    String? model,
    ContextDepth depth = ContextDepth.standard,
    List<LlmModel> accountModels = const [],
    bool includeStudioHint = true,
    bool studioMode = false,
  }) async {
    final session = await auth.ensureFreshSession();
    final brief = await SessionBrief.build(
      focusSessionId: focusSessionId,
      depth: depth,
    );
    final studio = includeStudioHint ? '\n\n$kStudioBuildPrompt' : '';
    final mode = studioMode
        ? '\nThe user is in Studio. Prefer a dashboard JSON they can save.\n'
        : '';
    final instructions =
        '$_kCoach$mode\n\nSession brief (local phone data, depth=${depth.name}):\n$brief$studio';

    final models = <String>[];
    if (model != null && model.isNotEmpty) models.add(model);
    for (final item in accountModels) {
      if (!models.contains(item.id)) models.add(item.id);
    }
    if (models.isEmpty) {
      models.addAll(kFallbackChatModels.map((m) => m.id));
    }

    Object? lastError;
    for (final candidate in models) {
      try {
        return await _complete(
          session: session,
          model: candidate,
          instructions: instructions,
          history: history,
          question: question,
        );
      } catch (e) {
        lastError = e;
        if (_isRetryableModelError(e.toString())) {
          continue;
        }
        rethrow;
      }
    }
    throw Exception(lastError?.toString() ?? 'ChatGPT request failed');
  }

  Future<String> _complete({
    required OpenAiSession session,
    required String model,
    required String instructions,
    required List<ChatTurn> history,
    required String question,
  }) async {
    final request = http.Request('POST', Uri.parse(kCodexResponsesUrl));
    request.headers.addAll({
      'Authorization': 'Bearer ${session.accessToken}',
      if (session.accountId != null && session.accountId!.isNotEmpty) ...{
        'chatgpt-account-id': session.accountId!,
        'ChatGPT-Account-Id': session.accountId!,
      },
      'OpenAI-Beta': 'responses=experimental',
      'originator': 'codex_cli_rs',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode(
      buildCodexChatBody(
        model: model,
        instructions: instructions,
        history: history,
        question: question,
      ),
    );

    final streamed = await _http.send(request);
    if (streamed.statusCode == 401) {
      final fresh = await auth.refresh(session);
      return _complete(
        session: fresh,
        model: model,
        instructions: instructions,
        history: history,
        question: question,
      );
    }
    if (streamed.statusCode != 200) {
      final raw = await streamed.stream.bytesToString();
      throw Exception(friendlyChatGptError(streamed.statusCode, raw));
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
}

/// Codex ChatGPT backend: instructions at top level, no system/input extras.
/// A live 2026 Plus account accepted this exact shape (HTTP 200 SSE).
Map<String, dynamic> buildCodexChatBody({
  required String model,
  required String instructions,
  required List<ChatTurn> history,
  required String question,
}) {
  final input = <Map<String, dynamic>>[
    for (final turn in history)
      if (turn.role == 'user' || turn.role == 'assistant') _userish(turn.role, turn.text),
    _userish('user', question),
  ];
  return {
    'model': model,
    'stream': true,
    'store': false,
    'instructions': instructions,
    'input': input,
  };
}

Map<String, dynamic> _userish(String role, String text) {
  return {
    'role': role,
    'content': [
      {'type': 'input_text', 'text': text},
    ],
  };
}

String friendlyChatGptError(int status, String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final detail = decoded['detail']?.toString();
      if (detail != null && detail.trim().isNotEmpty) {
        return 'ChatGPT: $detail';
      }
      final error = decoded['error'];
      if (error is Map) {
        final message = error['message']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return 'ChatGPT: $message';
        }
      }
    }
  } catch (_) {
    // Keep the status only — never dump tokens or HTML.
  }
  return 'ChatGPT HTTP $status';
}

bool _isRetryableModelError(String message) {
  final m = message.toLowerCase();
  return m.contains('model') &&
      (m.contains('not supported') || m.contains('unknown') || m.contains('invalid'));
}
