import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/ai/openai_sse.dart';

void main() {
  test('collects output_text deltas across split SSE chunks', () {
    final c = SseTextCollector();
    c.addChunk('event: response.output_text.delta\n');
    c.addChunk('data: {"type":"response.output_text.delta","delta":"Hel"}\n\n');
    c.addChunk('data: {"type":"response.output_text.delta","delta":"lo"}\n\n');
    c.addChunk('data: [DONE]\n\n');
    c.finish();
    expect(c.text, 'Hello');
  });
}
