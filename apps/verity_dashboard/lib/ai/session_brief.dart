import '../charts/chart_math.dart';
import '../metrics/hrv.dart';
import '../models/recording_session.dart';
import '../storage/local_db.dart';

/// How much of the on-phone recording the model is allowed to read.
///
/// Raw PPG is tens of thousands of rows (a 16-minute take is ~1.7 MB, not
/// 40 KB). Dumping every sample as text burns tokens, overflows context, and
/// makes point-level guesses worse — not better. Envelopes keep the shape.
enum ContextDepth {
  compact,
  standard,
  full;

  String get id => name;

  String get label => switch (this) {
        compact => 'Compact',
        standard => 'Standard',
        full => 'Full',
      };

  String get hint => switch (this) {
        compact => 'Index plus a thin HR sketch. Fewest tokens.',
        standard =>
          'Full-ish HR and PPI, plus PPG/motion envelopes. Recommended.',
        full => 'Denser envelopes. Still not every PPG sample.',
      };

  static ContextDepth fromId(String? id) {
    return ContextDepth.values.firstWhere(
      (d) => d.id == id,
      orElse: () => ContextDepth.standard,
    );
  }
}

/// Session context sent to ChatGPT when the user asks a question.
class SessionBrief {
  static Future<String> build({
    String? focusSessionId,
    int maxSessions = 8,
    ContextDepth depth = ContextDepth.standard,
  }) async {
    final db = LocalDb.instance;
    final sessions = await db.getSessions();
    if (sessions.isEmpty) {
      return 'The user has no recordings on this phone yet.';
    }

    final buf = StringBuffer();
    buf.writeln('Verity Dashboard local recordings (SQLite on the phone).');
    buf.writeln('Not medical data for diagnosis. Full-resolution table, not compressed.');
    buf.writeln('Do not invent PPG, motion, or HRV numbers that are not listed.');
    buf.writeln('Context depth: ${depth.name}.');
    buf.writeln(
      'PPG and motion traces here are min/max envelopes, not every sample. '
      'A 16-minute PPG take is ~40,000 rows / ~1.7 MB. A 25-minute HR-only '
      'take can be ~28 KB. Dumping 40k raw PPG values as text does not '
      'improve accuracy.',
    );
    buf.writeln();

    RecordingSession? focus;
    if (focusSessionId != null) {
      for (final s in sessions) {
        if (s.id == focusSessionId) focus = s;
      }
    }
    if (focus != null) {
      buf.writeln('FOCUS SESSION (user opened Ask AI from this take):');
      buf.writeln(await _describe(db, focus, detailed: true, depth: depth));
      buf.writeln();
    }

    buf.writeln('Recent sessions:');
    var extraDetailed = 0;
    final extraLimit = depth == ContextDepth.full ? 2 : 0;
    for (final s in sessions.take(maxSessions)) {
      if (focus != null && s.id == focus.id) continue;
      final extra = extraDetailed < extraLimit;
      if (extra) extraDetailed++;
      buf.writeln(
        await _describe(
          db,
          s,
          detailed: extra || depth == ContextDepth.full,
          depth: extra ? depth : ContextDepth.compact,
        ),
      );
    }
    return buf.toString();
  }

  static Future<String> _describe(
    LocalDb db,
    RecordingSession session, {
    required bool detailed,
    required ContextDepth depth,
  }) async {
    final counts = await db.getSampleTypeCounts(session.id);
    final bytes = await db.estimateSessionBytes(session.id);
    final start = DateTime.fromMillisecondsSinceEpoch(session.startTimeMs);
    final dur = session.duration;
    final durLabel = dur == null
        ? 'open'
        : '${dur.inMinutes}m ${dur.inSeconds % 60}s';
    final line = StringBuffer()
      ..write('- id=${session.id} ${session.name} (${session.source.label}) ')
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
        ..write(
          '  Note: no PPG. Size is small because HR is ~1 Hz. '
          'A 16-minute PPG take is ~40k rows.',
        );
    }

    if (depth == ContextDepth.compact) {
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

    final hrCap = depth == ContextDepth.full ? 2000 : 800;
    final ppiCap = depth == ContextDepth.full ? 1500 : 600;
    final envCap = depth == ContextDepth.full ? 400 : 160;

    if (counts.hr > 0) {
      final series = await db.getChartSeries(
        sessionId: session.id,
        signal: ChartSignal.hr,
        sessionStartMs: session.startTimeMs,
      );
      line.writeln();
      line.write(_seriesBlock('HR', series, cap: hrCap, envelope: series.length > hrCap));
    }
    if (counts.ppi > 0) {
      final series = await db.getChartSeries(
        sessionId: session.id,
        signal: ChartSignal.ppi,
        sessionStartMs: session.startTimeMs,
      );
      line.writeln();
      line.write(_seriesBlock('PPI', series, cap: ppiCap, envelope: series.length > ppiCap));
    }
    for (final signal in [ChartSignal.ppg, ChartSignal.acc, ChartSignal.gyro, ChartSignal.mag]) {
      final count = switch (signal) {
        ChartSignal.ppg => counts.ppg,
        ChartSignal.acc => counts.acc,
        ChartSignal.gyro => counts.gyro,
        ChartSignal.mag => counts.mag,
        _ => 0,
      };
      if (count == 0) continue;
      final series = await db.getChartSeries(
        sessionId: session.id,
        signal: signal,
        sessionStartMs: session.startTimeMs,
      );
      line.writeln();
      line.write(
        _seriesBlock(
          '${signal.column.toUpperCase()} envelope',
          series,
          cap: envCap,
          envelope: true,
        ),
      );
    }
    return line.toString();
  }

  static String _seriesBlock(
    String label,
    List<TimeValue> series, {
    required int cap,
    required bool envelope,
  }) {
    if (series.isEmpty) return '  $label: none';
    var min = series.first.value;
    var max = series.first.value;
    var sum = 0.0;
    for (final p in series) {
      if (p.value < min) min = p.value;
      if (p.value > max) max = p.value;
      sum += p.value;
    }
    final mean = sum / series.length;
    final shown = envelope || series.length > cap
        ? downsampleMinMax(series, cap)
        : series;
    final kind = envelope || series.length > cap
        ? 'min/max envelope, ${shown.length} of ${series.length} pts'
        : '${series.length} pts';
    return '  $label: n=${series.length} min=${formatLeanValue(min)} '
        'mean=${formatLeanValue(mean)} max=${formatLeanValue(max)} '
        '($kind): ${_fmtSeries(shown)}';
  }

  static String _fmtSeries(List<TimeValue> pts) {
    return pts
        .map((p) => '${p.seconds.toStringAsFixed(1)}=${formatLeanValue(p.value)}')
        .join(', ');
  }
}
