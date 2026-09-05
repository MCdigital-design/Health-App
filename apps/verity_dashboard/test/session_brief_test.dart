import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:verity_dashboard/ai/session_brief.dart';
import 'package:verity_dashboard/models/recording_session.dart';
import 'package:verity_dashboard/models/sensor_sample.dart';
import 'package:verity_dashboard/storage/local_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.databaseFileName = 'verity_session_brief_test.db';
  });

  test('session brief explains a long HR-only take vs PPG size', () async {
    final db = LocalDb.instance;
    await db.deleteAllSessions();
    final id = 'brief-${const Uuid().v4()}';
    await db.insertSession(RecordingSession(
      id: id,
      deviceId: '1F68643B',
      name: 'Live Session',
      startTimeMs: DateTime(2026, 9, 5, 13, 33).millisecondsSinceEpoch,
      endTimeMs: DateTime(2026, 9, 5, 13, 58).millisecondsSinceEpoch,
      dataTypes: 'hr,ppi',
    ));
    await db.insertSamples(id, [
      for (var i = 0; i < 20; i++)
        SensorSample(timestampMs: 1000 + i * 1000, hr: 120 + (i % 5)),
    ]);

    final text = await SessionBrief.build(focusSessionId: id);
    expect(text, contains('FOCUS SESSION'));
    expect(text, contains('HR 20'));
    expect(text, contains('PPG 0'));
    expect(text, contains('no PPG'));
    await db.deleteSession(id);
  });
}
