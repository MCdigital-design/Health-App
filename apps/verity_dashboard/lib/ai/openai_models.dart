import 'dart:convert';

import 'package:http/http.dart' as http;

import 'openai_device_auth.dart';

class LlmModel {
  final String id;
  final String label;

  const LlmModel({required this.id, this.label = ''});

  String get display => label.isEmpty ? id : label;

  @override
  bool operator ==(Object other) => other is LlmModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ModelCatalogResult {
  final List<LlmModel> models;
  final bool fromAccount;

  const ModelCatalogResult(this.models, {required this.fromAccount});
}

/// Fallback only when this account's catalog request fails. Never the only list.
const kFallbackChatModels = [
  LlmModel(id: 'gpt-5.6-terra', label: 'GPT-5.6 Terra'),
  LlmModel(id: 'gpt-5.6-luna', label: 'GPT-5.6 Luna'),
  LlmModel(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
  LlmModel(id: 'gpt-5.5', label: 'GPT-5.5'),
  LlmModel(id: 'gpt-5.4', label: 'GPT-5.4'),
  LlmModel(id: 'gpt-5.4-mini', label: 'GPT-5.4 mini'),
];

const _kPreferredDefaults = [
  'gpt-5.6-terra',
  'gpt-5.6-luna',
  'gpt-5.6-sol',
  'gpt-5.5',
  'gpt-5.4',
  'gpt-5.4-mini',
];

class OpenAiModelCatalog {
  final http.Client _http;
  OpenAiModelCatalog({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  /// Models this signed-in ChatGPT account can use. Adaptive — not a fixed list.
  Future<ModelCatalogResult> fetchForAccount(OpenAiSession session) async {
    final headers = <String, String>{
      'Authorization': 'Bearer ${session.accessToken}',
      'Accept': 'application/json',
      if (session.accountId != null && session.accountId!.isNotEmpty) ...{
        'ChatGPT-Account-Id': session.accountId!,
        'chatgpt-account-id': session.accountId!,
      },
    };
    final urls = [
      'https://chatgpt.com/backend-api/codex/models?client_version=1.0.0',
      'https://chatgpt.com/backend-api/codex/models',
    ];
    for (final url in urls) {
      try {
        final response = await _http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) continue;
        final models = parseCodexModelsJson(jsonDecode(response.body));
        if (models.isNotEmpty) {
          return ModelCatalogResult(models, fromAccount: true);
        }
      } catch (_) {
        continue;
      }
    }
    return const ModelCatalogResult(kFallbackChatModels, fromAccount: false);
  }
}

List<LlmModel> parseCodexModelsJson(Object? decoded) {
  final raw = <dynamic>[];
  if (decoded is Map) {
    if (decoded['models'] is List) {
      raw.addAll(decoded['models'] as List);
    } else if (decoded['data'] is List) {
      raw.addAll(decoded['data'] as List);
    }
  } else if (decoded is List) {
    raw.addAll(decoded);
  }

  final seen = <String>{};
  final out = <LlmModel>[];
  for (final item in raw) {
    String? id;
    var label = '';
    if (item is String) {
      id = item;
    } else if (item is Map) {
      id = (item['slug'] ?? item['id'] ?? item['model'] ?? item['name'])?.toString();
      label = (item['display_name'] ?? item['title'] ?? item['label'] ?? '').toString();
    }
    if (id == null || id.isEmpty || seen.contains(id)) continue;
    final lower = id.toLowerCase();
    if (lower.contains('image') ||
        lower.contains('realtime') ||
        lower.contains('audio') ||
        lower.contains('tts')) {
      continue;
    }
    seen.add(id);
    out.add(LlmModel(id: id, label: label));
  }
  return out;
}

/// Default to a current general model if the account has it; otherwise first listed.
String pickDefaultModel(List<LlmModel> models, {String? previous}) {
  if (models.isEmpty) return kFallbackChatModels.first.id;
  if (previous != null && models.any((m) => m.id == previous)) return previous;
  for (final id in _kPreferredDefaults) {
    if (models.any((m) => m.id == id)) return id;
  }
  return models.first.id;
}
