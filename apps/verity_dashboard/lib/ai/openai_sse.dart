import 'dart:convert';

/// Minimal SSE accumulator for the Codex `/responses` stream.
class SseTextCollector {
  final StringBuffer _carry = StringBuffer();
  final StringBuffer _text = StringBuffer();

  String get text => _text.toString();

  void addChunk(String chunk) {
    _carry.write(chunk);
    final raw = _carry.toString().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final parts = raw.split('\n\n');
    _carry
      ..clear()
      ..write(parts.removeLast());
    for (final block in parts) {
      _consumeBlock(block);
    }
  }

  void finish() {
    if (_carry.isNotEmpty) {
      _consumeBlock(_carry.toString());
      _carry.clear();
    }
  }

  void _consumeBlock(String block) {
    if (block.trim().isEmpty) return;
    final dataLines = <String>[];
    for (final line in block.split('\n')) {
      if (line.startsWith(':')) continue;
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) return;
    final data = dataLines.join('\n');
    if (data == '[DONE]') return;
    _ingestJson(data);
  }

  void _ingestJson(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      final type = decoded['type']?.toString() ?? '';
      if (type == 'response.output_text.delta') {
        final delta = decoded['delta']?.toString();
        if (delta != null) _text.write(delta);
        return;
      }
      final outputText = decoded['output_text']?.toString();
      if (outputText != null && outputText.isNotEmpty && _text.isEmpty) {
        _text.write(outputText);
      }
    } catch (_) {
      // Incomplete JSON stays in the carry buffer for the next chunk.
    }
  }
}
