import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/models/time_series_buffer.dart';

void main() {
  group('TimeSeriesBuffer', () {
    test('x-axis stays monotonic and never collides after eviction', () {
      // This is a regression test for the original bug: charting code used
      // `list.length` as the x-coordinate for new points, which stopped
      // advancing (and started colliding) once a fixed-size list began
      // evicting old entries, collapsing the line into a single x position.
      final buffer = TimeSeriesBuffer(retention: const Duration(seconds: 5));
      final baseMs = 1000000;
      // Add far more points than any reasonable "window" would show, well
      // past the retention window, to force pruning.
      for (var i = 0; i < 500; i++) {
        buffer.add(baseMs + i * 100, i.toDouble());
      }

      final spots = buffer.spotsForTimeframe(ChartTimeframe.realtime, now: baseMs + 499 * 100);
      expect(spots, isNotEmpty);

      final xs = spots.map((s) => s.x).toList();
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]), reason: 'x must be strictly increasing, no collisions');
      }
      // Real-time window is 15s; verify nothing older leaked in.
      expect(xs.first, greaterThanOrEqualTo(-15.001));
      expect(xs.last, closeTo(0, 0.001));
    });

    test('prunes points older than retention', () {
      final buffer = TimeSeriesBuffer(retention: const Duration(seconds: 10));
      buffer.add(0, 1.0);
      buffer.add(5000, 2.0);
      buffer.add(20000, 3.0); // more than 10s after the first point

      final spots = buffer.spotsForTimeframe(ChartTimeframe.m5, now: 20000);
      // Only points within 10s retention of the latest add should survive.
      expect(spots.map((s) => s.y), isNot(contains(1.0)));
    });

    test('aggregates into buckets for larger timeframes, reducing point count', () {
      final buffer = TimeSeriesBuffer(retention: const Duration(minutes: 10));
      // Simulate ~55Hz PPG for 5 seconds => ~275 raw points.
      final baseMs = 0;
      for (var i = 0; i < 275; i++) {
        buffer.add(baseMs + (i * 1000 / 55).round(), (i % 10).toDouble());
      }

      final realtimeSpots = buffer.spotsForTimeframe(ChartTimeframe.realtime, now: 5000);
      final bucketedSpots = buffer.spotsForTimeframe(ChartTimeframe.s1, now: 5000);

      expect(realtimeSpots.length, greaterThan(bucketedSpots.length));
      // 1s buckets over a several-second window should produce roughly one
      // point per second, not one per raw sample.
      expect(bucketedSpots.length, lessThanOrEqualTo(30));
    });

    test('yRangeForTimeframe pads a flat series so it does not divide by zero', () {
      final buffer = TimeSeriesBuffer();
      buffer.add(0, 70.0);
      buffer.add(1000, 70.0);
      final range = buffer.yRangeForTimeframe(ChartTimeframe.realtime, now: 1000);
      expect(range, isNotNull);
      expect(range!.max, greaterThan(range.min));
    });

    test('yRangeForTimeframe snaps off the raw sample max', () {
      final buffer = TimeSeriesBuffer();
      final now = 600000;
      buffer.add(now - 180000, 160.0);
      buffer.add(now, 125.0);
      final range = buffer.yRangeForTimeframe(ChartTimeframe.s30, now: now);
      expect(range, isNotNull);
      expect(range!.max, isNot(164));
      expect(range.max % range.interval, 0);
      expect(range.min % range.interval, 0);
    });

    test('timeframe chips name the visible window, not the bucket', () {
      expect(ChartTimeframe.s1.label, '30s');
      expect(ChartTimeframe.s30.label, '10m');
      expect(ChartTimeframe.s30.window, const Duration(minutes: 10));
    });

    test('returns empty spots for an empty buffer instead of throwing', () {
      final buffer = TimeSeriesBuffer();
      expect(buffer.spotsForTimeframe(ChartTimeframe.realtime), isEmpty);
      expect(buffer.yRangeForTimeframe(ChartTimeframe.realtime), isNull);
    });

    test('lastValue and lastTimestampMs track the most recent sample', () {
      final buffer = TimeSeriesBuffer();
      buffer.add(100, 42.0);
      buffer.add(200, 99.0);
      expect(buffer.lastValue, 99.0);
      expect(buffer.lastTimestampMs, 200);
    });
  });
}
