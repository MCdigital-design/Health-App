import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../charts/chart_math.dart';
import '../models/recording_session.dart';
import '../models/sensor_sample.dart';

enum ChartSignal { hr, ppg, acc, gyro, mag }

extension ChartSignalColumn on ChartSignal {
  String get column => switch (this) {
        ChartSignal.hr => 'hr',
        ChartSignal.ppg => 'ppg',
        ChartSignal.acc => 'acc',
        ChartSignal.gyro => 'gyro',
        ChartSignal.mag => 'mag',
      };
}

class LocalDb {
  static final LocalDb instance = LocalDb._internal();
  static Database? _db;

  /// Override in tests so parallel test isolates do not lock one file.
  static String databaseFileName = 'verity_dashboard.db';

  /// Bump when the schema changes. Migrations run in [_onUpgrade] so
  /// existing installs keep their data — sessions/samples are stored in the
  /// app's private SQLite database, which survives app restarts and
  /// in-place APK updates (it is only lost if the app is uninstalled or the
  /// user clears app storage from Android settings).
  static const int _schemaVersion = 2;

  LocalDb._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, databaseFileName);
    return openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions(
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            name TEXT NOT NULL,
            start_time_ms INTEGER NOT NULL,
            end_time_ms INTEGER,
            data_types TEXT NOT NULL,
            sample_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'live_app'
          )
        ''');
        await db.execute('''
          CREATE TABLE samples(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            timestamp_ms INTEGER NOT NULL,
            hr INTEGER,
            ppi TEXT,
            ppg TEXT,
            acc TEXT,
            gyro TEXT,
            mag TEXT,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_samples_session ON samples(session_id)');
        await db.execute('CREATE INDEX idx_samples_session_time ON samples(session_id, timestamp_ms)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE sessions ADD COLUMN source TEXT NOT NULL DEFAULT 'live_app'",
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_samples_session_time ON samples(session_id, timestamp_ms)',
          );
        }
      },
    );
  }

  Future<void> insertSession(RecordingSession session) async {
    final db = await database;
    await db.insert('sessions', session.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSessionSampleCount(String sessionId, int count, {int? endTimeMs}) async {
    final db = await database;
    final values = <String, dynamic>{'sample_count': count};
    if (endTimeMs != null) values['end_time_ms'] = endTimeMs;
    await db.update('sessions', values, where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<List<RecordingSession>> getSessions() async {
    final db = await database;
    final maps = await db.query('sessions', orderBy: 'start_time_ms DESC');
    return maps.map((m) => RecordingSession.fromMap(m)).toList();
  }

  Future<RecordingSession?> getSession(String sessionId) async {
    final db = await database;
    final maps = await db.query('sessions', where: 'id = ?', whereArgs: [sessionId]);
    if (maps.isEmpty) return null;
    return RecordingSession.fromMap(maps.first);
  }

  Future<void> insertSamples(String sessionId, List<SensorSample> samples) async {
    if (samples.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final sample in samples) {
      batch.insert('samples', sample.toMap(sessionId));
    }
    await batch.commit(noResult: true);
  }

  /// Full session rows. Do not silently cap this — the previous default of
  /// 5,000 dropped later HR rows whenever PPG (tens of Hz) filled the
  /// first page, which is why session detail showed "No data" for heart
  /// rate on a recording that had hundreds of HR samples.
  Future<List<SensorSample>> getSamples(String sessionId, {int? limit}) async {
    final db = await database;
    final maps = await db.query(
      'samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp_ms ASC',
      limit: limit,
    );
    return maps.map((m) => SensorSample.fromMap(m)).toList();
  }

  Future<List<SensorSample>> getSamplesWithSignal(
    String sessionId,
    ChartSignal signal, {
    int? limit,
  }) async {
    final db = await database;
    final column = signal.column;
    final maps = await db.query(
      'samples',
      where: 'session_id = ? AND $column IS NOT NULL',
      whereArgs: [sessionId],
      orderBy: 'timestamp_ms ASC',
      limit: limit,
    );
    return maps.map((m) => SensorSample.fromMap(m)).toList();
  }

  /// Chart-ready elapsed-second series for one signal. Queries only that
  /// column so a 40k-row PPG dump cannot hide 1 Hz HR.
  Future<List<TimeValue>> getChartSeries({
    required String sessionId,
    required ChartSignal signal,
    required int sessionStartMs,
  }) async {
    final samples = await getSamplesWithSignal(sessionId, signal);
    final pairs = <(int, double)>[];
    for (final s in samples) {
      final value = switch (signal) {
        ChartSignal.hr => s.hr?.toDouble(),
        ChartSignal.ppg => s.ppgChannel0,
        ChartSignal.acc => s.accMagnitude,
        ChartSignal.gyro => s.gyroMagnitude,
        ChartSignal.mag => s.magMagnitude,
      };
      if (value != null) pairs.add((s.timestampMs, value));
    }
    return elapsedSeries(samples: pairs, sessionStartMs: sessionStartMs);
  }

  Future<int> getSampleCount(String sessionId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM samples WHERE session_id = ?',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Per-signal-type counts, so a session with data can be distinguished
  /// from a session where a particular stream (e.g. HR) never delivered
  /// anything — instead of a single opaque "No HR data" message.
  Future<SessionSampleCounts> getSampleTypeCounts(String sessionId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) as total,
        COUNT(hr) as hr,
        COUNT(ppg) as ppg,
        COUNT(ppi) as ppi,
        COUNT(acc) as acc,
        COUNT(gyro) as gyro,
        COUNT(mag) as mag
      FROM samples WHERE session_id = ?
    ''', [sessionId]);
    if (rows.isEmpty) return SessionSampleCounts.empty;
    final r = rows.first;
    return SessionSampleCounts(
      total: r['total'] as int? ?? 0,
      hr: r['hr'] as int? ?? 0,
      ppg: r['ppg'] as int? ?? 0,
      ppi: r['ppi'] as int? ?? 0,
      acc: r['acc'] as int? ?? 0,
      gyro: r['gyro'] as int? ?? 0,
      mag: r['mag'] as int? ?? 0,
    );
  }

  /// Approximate on-disk bytes used by a session's rows (text-encoded
  /// numeric columns, so this is an estimate, not an exact page count).
  Future<int> estimateSessionBytes(String sessionId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(LENGTH(CAST(hr AS TEXT))), 0) +
        COALESCE(SUM(LENGTH(ppi)), 0) +
        COALESCE(SUM(LENGTH(ppg)), 0) +
        COALESCE(SUM(LENGTH(acc)), 0) +
        COALESCE(SUM(LENGTH(gyro)), 0) +
        COALESCE(SUM(LENGTH(mag)), 0) +
        (COUNT(*) * 16) as bytes
      FROM samples WHERE session_id = ?
    ''', [sessionId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<bool> sessionExistsForExternalId(String externalId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [externalId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await database;
    await db.delete('samples', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<void> deleteAllSessions() async {
    final db = await database;
    await db.delete('samples');
    await db.delete('sessions');
  }

  /// On-disk estimate for every session, one query.
  Future<Map<String, int>> estimateAllSessionBytes() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        session_id,
        COALESCE(SUM(LENGTH(CAST(hr AS TEXT))), 0) +
        COALESCE(SUM(LENGTH(ppi)), 0) +
        COALESCE(SUM(LENGTH(ppg)), 0) +
        COALESCE(SUM(LENGTH(acc)), 0) +
        COALESCE(SUM(LENGTH(gyro)), 0) +
        COALESCE(SUM(LENGTH(mag)), 0) +
        (COUNT(*) * 16) as bytes
      FROM samples
      GROUP BY session_id
    ''');
    return {
      for (final r in rows)
        (r['session_id'] as String): (r['bytes'] as int? ?? 0),
    };
  }
}
