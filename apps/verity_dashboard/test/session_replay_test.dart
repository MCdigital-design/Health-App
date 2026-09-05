import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:verity_dashboard/charts/chart_math.dart';
import 'package:verity_dashboard/models/recording_session.dart';
import 'package:verity_dashboard/models/sensor_sample.dart';
import 'package:verity_dashboard/storage/local_db.dart';

/// Replays the 16m 27s phone session: 987 HR + 41,376 PPG, Polar-epoch PPG
/// timestamps, no motion. This is the mix that made the old APK show
/// "No data" for Heart Rate.
const _sessionStart = 1757037867000;
const _polarEpoch = 946684800000;
const _hrCount = 987;
const _ppgCount = 41376;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.databaseFileName = 'verity_replay_test.db';
  });

  test('backend replay of the 16m session: 42,363 rows, HR not lost', () async {
    final db = LocalDb.instance;
    const id = 'replay-full';
    await db.deleteSession(id);
    final session = RecordingSession(
      id: id,
      deviceId: '1F68643B',
      name: 'Live Session',
      startTimeMs: _sessionStart,
      endTimeMs: _sessionStart + const Duration(minutes: 16, seconds: 27).inMilliseconds,
      dataTypes: 'hr,ppg',
      sampleCount: _hrCount + _ppgCount,
      source: SessionSource.liveApp,
    );
    await db.insertSession(session);
    await db.insertSamples(id, [
      for (var i = 0; i < _ppgCount; i++)
        SensorSample(
          timestampMs: _polarEpoch + (i * 1000 / 41.9).round(),
          ppg: [312800 + (i % 40) * 400],
        ),
      for (var i = 0; i < _hrCount; i++)
        SensorSample(
          timestampMs: _sessionStart + i * 1000,
          hr: 72 + (i % 12),
          ppi: [800 + (i % 40)],
        ),
    ]);

    final counts = await db.getSampleTypeCounts(id);
    expect(counts.total, _hrCount + _ppgCount);
    expect(counts.hr, _hrCount);
    expect(counts.ppi, _hrCount);
    expect(counts.ppg, _ppgCount);
    expect(counts.acc, 0);
    expect(counts.gyro, 0);
    expect(counts.mag, 0);

    final firstPage = await db.getSamples(id, limit: 5000);
    expect(firstPage.every((s) => s.hr == null), isTrue);

    final hr = await db.getChartSeries(
      sessionId: id,
      signal: ChartSignal.hr,
      sessionStartMs: session.startTimeMs,
    );
    expect(hr.length, _hrCount);
    expect(hr.last.seconds, closeTo(986, 0.01));

    final ppg = await db.getChartSeries(
      sessionId: id,
      signal: ChartSignal.ppg,
      sessionStartMs: session.startTimeMs,
    );
    expect(ppg.length, _ppgCount);
    expect(ppg.first.seconds, 0);

    final bytes = await db.estimateSessionBytes(id);
    expect(bytes, greaterThan(400 * 1024));
    expect(storageProjection(bytes: bytes, duration: session.duration), contains('Full-resolution'));

    await db.deleteSession(id);
    expect(await db.getSampleCount(id), 0);
  });
}
