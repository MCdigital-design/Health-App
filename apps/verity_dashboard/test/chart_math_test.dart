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

    test('rebases when Polar clock is tens of minutes behind the phone', () {
      // The 16-minute PPG chart plotted -59:44 … -43:20 because a 1-hour
      // slack treated a ~50-minute sensor offset as the session clock.
      const start = 1_000_000_000_000;
      final series = elapsedSeries(
        samples: [
          (start - 3584000, 300000),
          (start - 2600000, 310000),
        ],
        sessionStartMs: start,
      );
      expect(series.first.seconds, 0);
      expect(series.last.seconds, closeTo(984, 0.1));
      expect(series.every((p) => p.seconds >= 0), isTrue);
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

    test('snapRangeToNiceTicks drops ragged extras like 164 and 360680', () {
      final hr = snapRangeToNiceTicks(min: 104, max: 164);
      expect(hr.max, isNot(164));
      expect(hr.min % hr.interval, 0);
      expect(hr.max % hr.interval, 0);
      expect(niceTicks(hr.min, hr.max), isNot(contains(164)));

      final ppg = snapRangeToNiceTicks(min: 320000, max: 360680);
      expect(ppg.max, isNot(360680));
      expect(ppg.max % ppg.interval, 0);
      for (final tick in niceTicks(ppg.min, ppg.max)) {
        expect(formatAxisTick(tick).contains('.'), isFalse);
      }
    });

    test('formatAxisTick is a whole number; formatExactValue keeps the rest', () {
      expect(formatAxisTick(360680), '361k');
      expect(formatAxisTick(164), '164');
      expect(formatAxisTick(1.25), '1');
      expect(formatExactValue(360680), '360680');
      expect(formatExactValue(125.4), '125.4');
    });

    test('chart display is even; blue box keeps the captured fraction', () {
      const hrAvg = 158.93333333333334;
      const ppgAvg = 330032.4891472868;
      expect(formatLeanValue(hrAvg), '159');
      expect(formatLeanValue(ppgAvg), '330032');
      expect(formatCapturedValue(hrAvg), '158.933');
      expect(formatCapturedValue(ppgAvg), '330032.489');
      expect(formatTouchTooltip(y: hrAvg, unit: 'bpm', when: '-3m'), '159 bpm\n158.933\n-3m');
      expect(formatTouchTooltip(y: ppgAvg, when: '-2m'), '330032\n330032.489\n-2m');
      expect(formatLeanValue(hrAvg).contains('.'), isFalse);
      expect(formatTouchTooltip(y: hrAvg).contains('158.93333333333334'), isFalse);
      expect(formatTouchTooltip(y: ppgAvg).contains('330032.4891472868'), isFalse);
    });

    test('formatSessionClock is wall time, not elapsed or negative', () {
      final start = DateTime(2026, 9, 5, 13, 0).millisecondsSinceEpoch;
      expect(formatSessionClock(start, 0), '13:00');
      expect(formatSessionClock(start, 20 * 60), '13:20');
      expect(formatSessionClock(start, 987, windowSeconds: 987), '13:16');
      expect(formatSessionClock(start, -3584), isNot(contains('-')));
    });

    test('formatLiveAgo uses now / minutes, not -600s', () {
      expect(formatLiveAgo(0), 'now');
      expect(formatLiveAgo(-30), '-30s');
      expect(formatLiveAgo(-600), '-10m');
      expect(formatLiveAgo(-400), '-7m');
      expect(liveXInterval(600), 300);
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
