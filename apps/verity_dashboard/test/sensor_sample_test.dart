import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/metrics/hrv.dart';
import 'package:verity_dashboard/models/sensor_sample.dart';

void main() {
  test('empty PPI list is stored as null, not an empty string', () {
    final map = SensorSample(timestampMs: 1, hr: 70, ppi: []).toMap('s');
    expect(map['ppi'], isNull);
    expect(map['hr'], 70);
  });

  test('fromMap treats empty PPI as missing', () {
    final s = SensorSample.fromMap({
      'timestamp_ms': 1,
      'hr': 70,
      'ppi': '',
    });
    expect(s.ppi, isNull);
    expect(extractRrIntervals([s]), isEmpty);
  });

  test('fromMap parses fractional PPI milliseconds', () {
    final s = SensorSample.fromMap({
      'timestamp_ms': 1,
      'hr': 70,
      'ppi': '800.4,820.0',
    });
    expect(s.ppi, [800, 820]);
    expect(extractRrIntervals([s]), [800, 820]);
  });
}
