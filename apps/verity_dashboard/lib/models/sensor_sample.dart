import 'dart:math' as math;

class SensorSample {
  final int timestampMs;
  final int? hr;
  final List<int>? ppi;
  final List<int>? ppg;
  final List<double>? acc;
  final List<double>? gyro;
  final List<double>? mag;

  SensorSample({
    required this.timestampMs,
    this.hr,
    this.ppi,
    this.ppg,
    this.acc,
    this.gyro,
    this.mag,
  });

  Map<String, dynamic> toMap(String sessionId) {
    return {
      'session_id': sessionId,
      'timestamp_ms': timestampMs,
      'hr': hr,
      'ppi': _joinOrNull(ppi),
      'ppg': _joinOrNull(ppg),
      'acc': _joinOrNull(acc),
      'gyro': _joinOrNull(gyro),
      'mag': _joinOrNull(mag),
    };
  }

  double? get ppgChannel0 {
    if (ppg == null || ppg!.isEmpty) return null;
    return ppg!.first.toDouble();
  }

  double? get accMagnitude => _magnitude(acc);
  double? get gyroMagnitude => _magnitude(gyro);
  double? get magMagnitude => _magnitude(mag);

  static double? _magnitude(List<double>? xyz) {
    if (xyz == null || xyz.length < 3) return null;
    final x = xyz[0];
    final y = xyz[1];
    final z = xyz[2];
    return math.sqrt(x * x + y * y + z * z);
  }

  static String? _joinOrNull(List<Object>? values) {
    if (values == null || values.isEmpty) return null;
    return values.join(',');
  }

  static SensorSample fromMap(Map<String, dynamic> map) {
    List<int>? parseIntList(String? value) {
      if (value == null || value.isEmpty) return null;
      // Polar sometimes writes 800.4; int.tryParse would become 0 and
      // HRV would drop every beat (the 25-minute take looked like 0 beats).
      return value.split(',').map((e) {
        final asInt = int.tryParse(e.trim());
        if (asInt != null) return asInt;
        return double.tryParse(e.trim())?.round() ?? 0;
      }).toList();
    }

    List<double>? parseDoubleList(String? value) {
      if (value == null || value.isEmpty) return null;
      return value.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
    }

    return SensorSample(
      timestampMs: map['timestamp_ms'] as int,
      hr: map['hr'] as int?,
      ppi: parseIntList(map['ppi'] as String?),
      ppg: parseIntList(map['ppg'] as String?),
      acc: parseDoubleList(map['acc'] as String?),
      gyro: parseDoubleList(map['gyro'] as String?),
      mag: parseDoubleList(map['mag'] as String?),
    );
  }
}
