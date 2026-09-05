import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/widgets/collapsible_hint.dart';

void main() {
  testWidgets('hint body is hidden until expanded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CollapsibleHint(
            label: 'Why row counts differ',
            body: 'Nothing is compressed.',
          ),
        ),
      ),
    );
    expect(find.text('Why row counts differ'), findsOneWidget);
    expect(find.text('Nothing is compressed.'), findsNothing);

    await tester.tap(find.text('Why row counts differ'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing is compressed.'), findsOneWidget);
  });
}
