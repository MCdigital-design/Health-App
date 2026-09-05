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
      'ppi': ppi?.join(','),
      'ppg': ppg?.join(','),
      'acc': acc?.join(','),
      'gyro': gyro?.join(','),
      'mag': mag?.join(','),
    };
  }

  static SensorSample fromMap(Map<String, dynamic> map) {
    List<int>? parseIntList(String? value) {
      if (value == null || value.isEmpty) return null;
      return value.split(',').map((e) => int.tryParse(e) ?? 0).toList();
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
