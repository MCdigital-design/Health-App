/// Where a recorded session's data came from. Surfaced in the UI so users
/// can tell apart data captured live through this app from data imported
/// from the sensor's own memory or from a Polar Flow account.
enum SessionSource {
  liveApp('live_app', 'Recorded in app'),
  deviceExercise('device_exercise', 'From sensor'),
  polarFlow('polar_flow', 'From Polar Flow');

  final String value;
  final String label;
  const SessionSource(this.value, this.label);

  static SessionSource fromValue(String? value) {
    return SessionSource.values.firstWhere(
      (s) => s.value == value,
      orElse: () => SessionSource.liveApp,
    );
  }
}

class RecordingSession {
  final String id;
  final String deviceId;
  final String name;
  final int startTimeMs;
  final int? endTimeMs;
  final String dataTypes;
  final int sampleCount;
  final SessionSource source;

  RecordingSession({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.startTimeMs,
    this.endTimeMs,
    required this.dataTypes,
    this.sampleCount = 0,
    this.source = SessionSource.liveApp,
  });

  Duration? get duration =>
      endTimeMs != null ? Duration(milliseconds: endTimeMs! - startTimeMs) : null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'name': name,
      'start_time_ms': startTimeMs,
      'end_time_ms': endTimeMs,
      'data_types': dataTypes,
      'sample_count': sampleCount,
      'source': source.value,
    };
  }

  static RecordingSession fromMap(Map<String, dynamic> map) {
    return RecordingSession(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      name: map['name'] as String,
      startTimeMs: map['start_time_ms'] as int,
      endTimeMs: map['end_time_ms'] as int?,
      dataTypes: map['data_types'] as String,
      sampleCount: map['sample_count'] as int? ?? 0,
      source: SessionSource.fromValue(map['source'] as String?),
    );
  }
}

/// Per-signal-type sample counts for a session, used to diagnose exactly
/// what data a recording actually captured (e.g. distinguishing "HR never
/// streamed" from "HR streamed but the chart failed to render").
class SessionSampleCounts {
  final int total;
  final int hr;
  final int ppg;
  final int ppi;
  final int acc;
  final int gyro;
  final int mag;

  const SessionSampleCounts({
    required this.total,
    required this.hr,
    required this.ppg,
    required this.ppi,
    required this.acc,
    required this.gyro,
    required this.mag,
  });

  static const empty = SessionSampleCounts(
    total: 0, hr: 0, ppg: 0, ppi: 0, acc: 0, gyro: 0, mag: 0,
  );
}
