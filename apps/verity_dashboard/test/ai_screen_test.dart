import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:verity_dashboard/ai/openai_models.dart';
import 'package:verity_dashboard/screens/ai_screen.dart';
import 'package:verity_dashboard/storage/local_db.dart';

class _StubCatalog extends OpenAiModelCatalog {
  @override
  Future<ModelCatalogResult> fetchForAccount(session) async {
    return const ModelCatalogResult([
      LlmModel(id: 'gpt-5.6-terra', label: 'GPT-5.6 Terra'),
      LlmModel(id: 'account-only-model', label: 'Account Only'),
    ], fromAccount: true);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.databaseFileName = 'verity_ai_screen_test.db';
  });

  testWidgets('signed-out AI tab asks whoever is using the phone to sign in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: AiScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Use your ChatGPT account'), findsOneWidget);
    expect(find.text('Sign in with ChatGPT'), findsOneWidget);
    expect(find.text('Studio'), findsNothing);
  });

  testWidgets('signed-in AI tab offers Chat and Studio, then an account model list', (tester) async {
    SharedPreferences.setMockInitialValues({
      'openai_access_token': 'tok',
      'openai_refresh_token': 'ref',
      'openai_email': 'anyone@example.com',
      'openai_account_id': 'acct_test',
      'openai_plan': 'plus',
    });

    await tester.pumpWidget(MaterialApp(home: AiScreen(catalog: _StubCatalog())));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('anyone@example.com'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('Models from this ChatGPT account'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.text('GPT-5.6 Terra'), findsOneWidget);
    expect(find.text('Account Only'), findsNothing);
    expect(find.text('Standard'), findsOneWidget);

    await tester.tap(find.text('GPT-5.6 Terra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account Only').last);
    await tester.pumpAndSettle();
    expect(find.text('Account Only'), findsOneWidget);
  });
}
