import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/models/time_series_buffer.dart';
import 'package:verity_dashboard/widgets/live_chart.dart';

void main() {
  testWidgets('Live HR chart uses even Y ticks and now / -10m, not 164 or -600s', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final buffer = TimeSeriesBuffer();
    const now = 600000;
    buffer.add(now - 180000, 160);
    buffer.add(now, 125);
    final spots = buffer.spotsForTimeframe(ChartTimeframe.s30, now: now);
    final range = buffer.yRangeForTimeframe(ChartTimeframe.s30, now: now);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: LiveChart(
            spots: spots,
            title: 'Heart Rate',
            unit: 'bpm',
            color: Colors.redAccent,
            timeframe: ChartTimeframe.s30,
            yRange: range,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('last 10m'), findsOneWidget);
    expect(find.text('125 bpm'), findsOneWidget);
    expect(find.text('now'), findsWidgets);
    expect(find.text('-10m'), findsWidgets);
    expect(find.text('-600s'), findsNothing);
    expect(find.text('164'), findsNothing);
    expect(find.text('104'), findsNothing);
  });

  testWidgets('Live PPG chart hides the raw 360680 tick and keeps it in the chip', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final buffer = TimeSeriesBuffer();
    const now = 600000;
    buffer.add(now - 100000, 320000);
    buffer.add(now, 360680);
    final spots = [
      const FlSpot(-600, 320000),
      const FlSpot(0, 360680),
    ];
    final range = buffer.yRangeForTimeframe(ChartTimeframe.s30, now: now);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: LiveChart(
            spots: spots,
            title: 'PPG Waveform',
            color: Colors.blueAccent,
            timeframe: ChartTimeframe.s30,
            yRange: range,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('360680'), findsOneWidget);
    expect(find.text('360680'), findsOneWidget); // exact chip only
    // Axis must not also paint the raw max as a tick.
    final axisish = find.text('360680');
    expect(axisish, findsOneWidget);
    expect(find.text('last 10m'), findsOneWidget);
  });
}
