import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/charts/chart_math.dart';
import 'package:verity_dashboard/widgets/interactive_time_chart.dart';

void main() {
  testWidgets('session chart shows time on X and compact Y labels', (tester) async {
    final points = <TimeValue>[
      for (var i = 0; i <= 987; i++)
        TimeValue(i.toDouble(), 312800 + (i % 40) * 400.0),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: InteractiveTimeChart(
            title: 'PPG (first channel)',
            unit: 'raw',
            color: Colors.blueAccent,
            points: points,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PPG (first channel)'), findsOneWidget);
    expect(find.text('0:00'), findsWidgets);
    expect(find.textContaining('16:'), findsWidgets);
    expect(find.text('No data'), findsNothing);
    // Compact labels, not the wrapped "329.\n7K" bug.
    expect(find.textContaining('k'), findsWidgets);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pinch or drag'), findsOneWidget);
  });

  testWidgets('empty HR series explains the gap instead of drawing a blank axis', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InteractiveTimeChart(
            title: 'Heart Rate',
            unit: 'bpm',
            color: Colors.redAccent,
            points: [],
            emptyLabel: 'No heart-rate samples in this recording',
          ),
        ),
      ),
    );
    expect(find.text('No heart-rate samples in this recording'), findsOneWidget);
  });
}
