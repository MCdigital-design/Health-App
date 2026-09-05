import '../charts/chart_math.dart';
import '../metrics/hrv.dart';
import '../models/recording_session.dart';
import '../storage/local_db.dart';

/// Compact, no-raw-PPG summary sent to ChatGPT when the user asks a question.
class SessionBrief {
  static Future<String> build({String? focusSessionId, int maxSessions = 8}) async {
    final db = LocalDb.instance;
    final sessions = await db.getSessions();
    if (sessions.isEmpty) {
      return 'The user has no recordings on this phone yet.';
    }

    final buf = StringBuffer();
    buf.writeln('Verity Dashboard local recordings (SQLite on the phone).');
    buf.writeln('Not medical data for diagnosis. Full-resolution table, not compressed.');
    buf.writeln('Do not invent PPG, motion, or HRV numbers that are not listed.');
    buf.writeln();

    RecordingSession? focus;
    if (focusSessionId != null) {
      for (final s in sessions) {
        if (s.id == focusSessionId) focus = s;
      }
    }
    if (focus != null) {
      buf.writeln('FOCUS SESSION (user opened Ask AI from this take):');
      buf.writeln(await _describe(db, focus, detailed: true));
      buf.writeln();
    }

    buf.writeln('Recent sessions:');
    for (final s in sessions.take(maxSessions)) {
      if (focus != null && s.id == focus.id) continue;
      buf.writeln(await _describe(db, s, detailed: false));
    }
    return buf.toString();
  }

  static Future<String> _describe(
    LocalDb db,
    RecordingSession session, {
    required bool detailed,
  }) async {
    final counts = await db.getSampleTypeCounts(session.id);
    final bytes = await db.estimateSessionBytes(session.id);
    final start = DateTime.fromMillisecondsSinceEpoch(session.startTimeMs);
    final dur = session.duration;
    final durLabel = dur == null
        ? 'open'
        : '${dur.inMinutes}m ${dur.inSeconds % 60}s';
    final line = StringBuffer()
      ..write('- ${session.name} (${session.source.label}) ')
      ..write('${start.toIso8601String()} · $durLabel · ')
      ..write('${formatBytes(bytes)} · ${counts.total} rows · ')
      ..write('HR ${counts.hr}, PPG ${counts.ppg}, PPI ${counts.ppi}, ')
      ..write('ACC ${counts.acc}, gyro ${counts.gyro}, mag ${counts.mag}');

    if (!detailed) return line.toString();

    final hrRows = await db.getSamplesWithSignal(session.id, ChartSignal.hr);
    final hrv = computeHrv(hrRows);
    line
      ..writeln()
      ..write('  HR min/mean/max: ${hrv.minHr ?? '—'} / ${hrv.meanHr ?? '—'} / ${hrv.maxHr ?? '—'}')
      ..write(' · RMSSD ${hrv.rmssd?.round() ?? '—'}')
      ..write(' · SDNN ${hrv.sdnn?.round() ?? '—'}')
      ..write(' · pNN50 ${hrv.pnn50 == null ? '—' : '${hrv.pnn50!.round()}%'}')
      ..write(' · beats ${hrv.intervalCount}');
    if (counts.ppg == 0 && counts.hr > 0) {
      line
        ..writeln()
        ..write('  Note: no PPG. Size is small because HR is ~1 Hz. A 16-minute PPG take is ~40k rows.');
    }
    if (hrRows.length >= 2) {
      final step = (hrRows.length / 40).ceil();
      final pts = <String>[];
      for (var i = 0; i < hrRows.length; i += step) {
        final hr = hrRows[i].hr;
        if (hr == null) continue;
        final t = DateTime.fromMillisecondsSinceEpoch(hrRows[i].timestampMs);
        pts.add('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}=$hr');
      }
      if (pts.isNotEmpty) {
        line
          ..writeln()
          ..write('  HR trace (downsampled, bpm): ${pts.join(', ')}');
      }
    }
    return line.toString();
  }
}
