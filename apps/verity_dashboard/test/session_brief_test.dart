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
    expect(text, contains('id=$id'));
    await db.deleteSession(id);
  });

  test('standard brief includes HR points; compact stays thinner', () async {
    final db = LocalDb.instance;
    await db.deleteAllSessions();
    final id = 'brief-depth-${const Uuid().v4()}';
    await db.insertSession(RecordingSession(
      id: id,
      deviceId: '1F68643B',
      name: 'PPG take',
      startTimeMs: DateTime(2026, 9, 5, 10).millisecondsSinceEpoch,
      endTimeMs: DateTime(2026, 9, 5, 10, 16).millisecondsSinceEpoch,
      dataTypes: 'hr,ppg',
    ));
    await db.insertSamples(id, [
      for (var i = 0; i < 30; i++)
        SensorSample(timestampMs: 1000 + i * 1000, hr: 90 + i),
      for (var i = 0; i < 200; i++)
        SensorSample(timestampMs: 1000 + i * 50, ppg: [300000 + i, 300100 + i]),
    ]);

    final compact = await SessionBrief.build(
      focusSessionId: id,
      depth: ContextDepth.compact,
    );
    final standard = await SessionBrief.build(
      focusSessionId: id,
      depth: ContextDepth.standard,
    );

    expect(compact, contains('HR trace (downsampled, bpm)'));
    expect(compact, isNot(contains('PPG envelope')));
    expect(standard, contains('PPG envelope'));
    expect(standard, contains('min/max envelope'));
    expect(standard, contains('of 200 pts'));
    expect(standard.length, greaterThan(compact.length));
    await db.deleteSession(id);
  });
}
