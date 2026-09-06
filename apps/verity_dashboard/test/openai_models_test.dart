import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/ai/openai_models.dart';

void main() {
  test('parseCodexModelsJson reads slug/id lists and skips media models', () {
    final models = parseCodexModelsJson({
      'models': [
        {'slug': 'gpt-5.6-terra', 'display_name': 'GPT-5.6 Terra'},
        {'id': 'gpt-5.6-sol', 'title': 'GPT-5.6 Sol'},
        'gpt-5.5',
        {'id': 'gpt-image-1', 'display_name': 'Image'},
        {'slug': 'gpt-5.6-terra'},
      ],
    });
    expect(models.map((m) => m.id).toList(), ['gpt-5.6-terra', 'gpt-5.6-sol', 'gpt-5.5']);
    expect(models.first.display, 'GPT-5.6 Terra');
  });

  test('parseCodexModelsJson accepts a data array or a raw list', () {
    expect(parseCodexModelsJson({'data': [{'id': 'gpt-5.6-luna'}]}).single.id, 'gpt-5.6-luna');
    expect(parseCodexModelsJson(['only-this']).single.id, 'only-this');
    expect(parseCodexModelsJson({'models': []}), isEmpty);
  });

  test('pickDefaultModel keeps a previous id when the account still has it', () {
    const models = [
      LlmModel(id: 'acct-only-model', label: 'Account model'),
      LlmModel(id: 'gpt-5.6-sol'),
    ];
    expect(pickDefaultModel(models, previous: 'acct-only-model'), 'acct-only-model');
    expect(pickDefaultModel(models, previous: 'retired-5.4'), 'gpt-5.6-sol');
    expect(pickDefaultModel(const []), kFallbackChatModels.first.id);
  });
}
