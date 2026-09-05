import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:verity_dashboard/models/recording_session.dart';
import 'package:verity_dashboard/models/sensor_sample.dart';
import 'package:verity_dashboard/storage/local_db.dart';

const _uuid = Uuid();

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('LocalDb', () {
    test('round-trips session source (live_app / device_exercise / polar_flow)', () async {
      final db = LocalDb.instance;
      final liveId = 'test-live-${_uuid.v4()}';
      final deviceId = 'test-device-${_uuid.v4()}';
      final flowId = 'test-flow-${_uuid.v4()}';

      await db.insertSession(RecordingSession(
        id: liveId,
        deviceId: 'sensor1',
        name: 'Live',
        startTimeMs: 1000,
        dataTypes: 'hr,ppg',
        source: SessionSource.liveApp,
      ));
      await db.insertSession(RecordingSession(
        id: deviceId,
        deviceId: 'sensor1',
        name: 'Device',
        startTimeMs: 1000,
        dataTypes: 'hr',
        source: SessionSource.deviceExercise,
      ));
      await db.insertSession(RecordingSession(
        id: flowId,
        deviceId: 'polar_flow',
        name: 'Flow',
        startTimeMs: 1000,
        dataTypes: 'hr',
        source: SessionSource.polarFlow,
      ));

      final live = await db.getSession(liveId);
      final device = await db.getSession(deviceId);
      final flow = await db.getSession(flowId);

      expect(live!.source, SessionSource.liveApp);
      expect(device!.source, SessionSource.deviceExercise);
      expect(flow!.source, SessionSource.polarFlow);

      await db.deleteSession(liveId);
      await db.deleteSession(deviceId);
      await db.deleteSession(flowId);
    });

    test('sessions default to live_app source when none specified', () async {
      final db = LocalDb.instance;
      final id = 'test-default-${_uuid.v4()}';
      await db.insertSession(RecordingSession(
        id: id,
        deviceId: 'sensor1',
        name: 'Default',
        startTimeMs: 1000,
        dataTypes: 'hr',
      ));
      final session = await db.getSession(id);
      expect(session!.source, SessionSource.liveApp);
      await db.deleteSession(id);
    });

    test('getSampleTypeCounts distinguishes which signals actually recorded data', () async {
      // This directly covers the bug report: a session showed a non-zero
      // total sample count but an opaque "No HR data" message with no way
      // to tell whether HR ever streamed at all.
      final db = LocalDb.instance;
      final id = 'test-counts-${_uuid.v4()}';
      await db.insertSession(RecordingSession(
        id: id,
        deviceId: 'sensor1',
        name: 'Mixed',
        startTimeMs: 1000,
        dataTypes: 'hr,ppg',
      ));
      await db.insertSamples(id, [
        SensorSample(timestampMs: 1, hr: 70),
        SensorSample(timestampMs: 2, hr: 72),
        SensorSample(timestampMs: 3, ppg: [100, 101]),
        SensorSample(timestampMs: 4, ppg: [102, 103]),
        SensorSample(timestampMs: 5, ppg: [104, 105]),
      ]);

      final counts = await db.getSampleTypeCounts(id);
      expect(counts.total, 5);
      expect(counts.hr, 2);
      expect(counts.ppg, 3);
      expect(counts.acc, 0);

      await db.deleteSession(id);
    });

    test('sessionExistsForExternalId prevents duplicate imports', () async {
      final db = LocalDb.instance;
      final id = 'polarflow:test-${_uuid.v4()}';
      expect(await db.sessionExistsForExternalId(id), isFalse);

      await db.insertSession(RecordingSession(
        id: id,
        deviceId: 'polar_flow',
        name: 'Imported',
        startTimeMs: 1000,
        dataTypes: 'hr',
        source: SessionSource.polarFlow,
      ));

      expect(await db.sessionExistsForExternalId(id), isTrue);
      await db.deleteSession(id);
      expect(await db.sessionExistsForExternalId(id), isFalse);
    });

    test('deleteSession cascades to samples', () async {
      final db = LocalDb.instance;
      final id = 'test-cascade-${_uuid.v4()}';
      await db.insertSession(RecordingSession(
        id: id,
        deviceId: 'sensor1',
        name: 'ToDelete',
        startTimeMs: 1000,
        dataTypes: 'hr',
      ));
      await db.insertSamples(id, [SensorSample(timestampMs: 1, hr: 70)]);
      expect(await db.getSampleCount(id), 1);

      await db.deleteSession(id);
      expect(await db.getSampleCount(id), 0);
      expect(await db.getSession(id), isNull);
    });
  });
}
