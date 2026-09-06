import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/ai/studio_spec.dart';
import 'package:verity_dashboard/widgets/studio_dashboard_view.dart';

void main() {
  testWidgets('Studio dashboard renders metric and note widgets', (tester) async {
    const spec = StudioDashboardSpec(
      title: 'Recovery',
      widgets: [
        StudioWidget(type: 'metric', title: 'RMSSD', value: '42', unit: 'ms'),
        StudioWidget(type: 'note', title: 'Read', text: 'Not a medical device.'),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StudioDashboardView(spec: spec)),
      ),
    );

    expect(find.text('RMSSD'), findsOneWidget);
    expect(find.text('42 ms'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Not a medical device.'), findsOneWidget);
  });
}
