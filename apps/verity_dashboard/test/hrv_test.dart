import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/metrics/hrv.dart';
import 'package:verity_dashboard/models/sensor_sample.dart';

void main() {
  test('computeHrv from beat intervals — RMSSD / SDNN / pNN50', () {
    final samples = [
      SensorSample(timestampMs: 0, hr: 75, ppi: [800]),
      SensorSample(timestampMs: 800, hr: 73, ppi: [820]),
      SensorSample(timestampMs: 1620, hr: 76, ppi: [790]),
      SensorSample(timestampMs: 2410, hr: 74, ppi: [810]),
    ];
    final hrv = computeHrv(samples);
    expect(hrv.intervalCount, 4);
    expect(hrv.hasHrv, isTrue);
    expect(hrv.meanHr, 75);
    expect(hrv.minHr, 73);
    expect(hrv.maxHr, 76);
    expect(hrv.rmssd, greaterThan(20));
    expect(hrv.rmssd, lessThan(30));
    expect(hrv.sdnn, greaterThan(5));
    expect(hrv.pnn50, 0);
  });

  test('drops implausible Polar glitch intervals', () {
    final samples = [
      SensorSample(timestampMs: 0, hr: 70, ppi: [50, 800, 9000, 820]),
    ];
    expect(extractRrIntervals(samples), [800, 820]);
  });

  test('no HRV when only PPG rows exist', () {
    final hrv = computeHrv([
      SensorSample(timestampMs: 0, ppg: [300000]),
    ]);
    expect(hrv.hasHrv, isFalse);
    expect(hrv.intervalCount, 0);
  });
}
