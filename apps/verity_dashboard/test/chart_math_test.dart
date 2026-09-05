import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/charts/chart_math.dart';

void main() {
  group('elapsedSeries', () {
    test('uses session start when samples are on the phone clock', () {
      const start = 1_000_000;
      final series = elapsedSeries(
        samples: [
          (start + 1000, 70),
          (start + 2000, 72),
        ],
        sessionStartMs: start,
      );
      expect(series.map((p) => p.seconds), [1.0, 2.0]);
    });

    test('falls back to first sample when Polar timestamps are in another epoch', () {
      // Polar PPG often arrives with a sensor clock far from Unix time.
      // Heart-rate rows use DateTime.now(), so a shared ORDER BY hid HR
      // behind tens of thousands of earlier PPG rows.
      const polarEpoch = 946684800000; // 2000-01-01
      final series = elapsedSeries(
        samples: [
          (polarEpoch, 300000),
          (polarEpoch + 1000, 301000),
          (polarEpoch + 2000, 302000),
        ],
        sessionStartMs: DateTime(2026, 9, 5).millisecondsSinceEpoch,
      );
      expect(series.first.seconds, 0);
      expect(series.last.seconds, 2);
    });
  });

  group('downsampleMinMax', () {
    test('keeps endpoints and reduces 40k-class series without averaging away peaks', () {
      final points = <TimeValue>[
        for (var i = 0; i < 40000; i++)
          TimeValue(i / 40.0, i == 20000 ? 9999 : (i % 50).toDouble()),
      ];
      final down = downsampleMinMax(points, 400);
      expect(down.length, lessThan(500));
      expect(down.length, greaterThan(50));
      expect(down.first.seconds, points.first.seconds);
      expect(down.last.seconds, points.last.seconds);
      expect(down.any((p) => p.value == 9999), isTrue);
    });
  });

  group('axis labels', () {
    test('formatAxisNumber stays on one line for large PPG values', () {
      expect(formatAxisNumber(329700), '330k');
      expect(formatAxisNumber(312800), '313k');
      expect(formatAxisNumber(72), '72');
      expect(formatAxisNumber(1.25), '1.25');
    });

    test('formatElapsed uses m:ss and h:mm:ss', () {
      expect(formatElapsed(0), '0:00');
      expect(formatElapsed(87), '1:27');
      expect(formatElapsed(987), '16:27');
      expect(formatElapsed(3661), '1:01:01');
    });

    test('niceTicks do not overlap and cover the window', () {
      final ticks = niceTicks(312800, 329700);
      expect(ticks.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], greaterThan(ticks[i - 1]));
      }
    });
  });

  group('storageProjection', () {
    test('describes a full table and an hourly rate for the 16-minute session', () {
      // 1.71 MB over 16m27s ≈ the user's screenshot.
      final text = storageProjection(
        bytes: 1793065,
        duration: const Duration(minutes: 16, seconds: 27),
      );
      expect(text, contains('Full-resolution SQLite table'));
      expect(text, contains('not compressed'));
      expect(text.toLowerCase(), contains('hour'));
    });
  });
}
