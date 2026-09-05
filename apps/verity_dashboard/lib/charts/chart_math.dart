import 'dart:math' as math;

/// A single chart sample in elapsed seconds from the session start (or from
/// the first sample, when the sensor clock is in a different epoch).
class TimeValue {
  final double seconds;
  final double value;

  const TimeValue(this.seconds, this.value);
}

/// Convert raw `(timestampMs, value)` pairs into elapsed-second points.
///
/// Heart-rate rows in this app are stamped with the phone clock. Polar PPG
/// and motion samples often use the sensor clock, which can be years away
/// from Unix time. If most points sit near [sessionStartMs] we use that as
/// t=0; otherwise we fall back to the first sample so the waveform still
/// has a usable time axis.
List<TimeValue> elapsedSeries({
  required List<(int timestampMs, double value)> samples,
  required int sessionStartMs,
}) {
  if (samples.isEmpty) return const [];
  final sorted = [...samples]..sort((a, b) => a.$1.compareTo(b.$1));
  const dayMs = 24 * 60 * 60 * 1000;
  final nearSession = sorted.where((s) {
    final delta = s.$1 - sessionStartMs;
    return delta >= -60 * 60 * 1000 && delta <= dayMs;
  }).length;
  final useSessionClock = nearSession >= (sorted.length / 2).ceil();
  final origin = useSessionClock ? sessionStartMs : sorted.first.$1;
  return [
    for (final s in sorted) TimeValue((s.$1 - origin) / 1000.0, s.$2),
  ];
}

/// Min/max envelope downsample. Preserves peaks (unlike averaging) so a
/// 40k-point PPG trace still looks like the raw waveform when zoomed out,
/// then reveals more detail as the visible window shrinks.
List<TimeValue> downsampleMinMax(List<TimeValue> points, int maxPoints) {
  if (points.length <= maxPoints || maxPoints < 4) return points;
  // Two extremes per bucket, plus endpoints.
  final bucketCount = math.max(2, (maxPoints - 2) ~/ 2);
  final first = points.first;
  final last = points.last;
  final span = last.seconds - first.seconds;
  if (span <= 0) return points;

  final buckets = List.generate(bucketCount, (_) => <TimeValue>[]);
  for (var i = 1; i < points.length - 1; i++) {
    final t = ((points[i].seconds - first.seconds) / span * bucketCount)
        .floor()
        .clamp(0, bucketCount - 1);
    buckets[t].add(points[i]);
  }

  final out = <TimeValue>[first];
  for (final bucket in buckets) {
    if (bucket.isEmpty) continue;
    var minP = bucket.first;
    var maxP = bucket.first;
    for (final p in bucket) {
      if (p.value < minP.value) minP = p;
      if (p.value > maxP.value) maxP = p;
    }
    if (minP.seconds <= maxP.seconds) {
      out.add(minP);
      if (!identical(minP, maxP)) out.add(maxP);
    } else {
      out.add(maxP);
      out.add(minP);
    }
  }
  out.add(last);
  return out;
}

(double, double) paddedRange(Iterable<double> values, {double pad = 0.12}) {
  final list = values.toList();
  if (list.isEmpty) return (0, 1);
  var min = list.first;
  var max = list.first;
  for (final v in list) {
    if (v < min) min = v;
    if (v > max) max = v;
  }
  if (min == max) {
    final slack = min.abs() < 1 ? 1.0 : min.abs() * 0.05;
    return (min - slack, max + slack);
  }
  final padding = (max - min) * pad;
  return (min - padding, max + padding);
}

/// Wilkinson-style "nice" tick step for a readable axis.
double niceStep(double range, {int tickCount = 4}) {
  if (range <= 0 || !range.isFinite) return 1;
  final rough = range / tickCount;
  final exp = (math.log(rough) / math.ln10).floor();
  final frac = rough / math.pow(10, exp);
  final niceFrac = frac < 1.5
      ? 1.0
      : frac < 3
          ? 2.0
          : frac < 7
              ? 5.0
              : 10.0;
  return niceFrac * math.pow(10, exp);
}

List<double> niceTicks(double min, double max, {int tickCount = 4}) {
  if (!min.isFinite || !max.isFinite || min == max) {
    return [min, max];
  }
  final step = niceStep(max - min, tickCount: tickCount);
  final start = (min / step).floor() * step;
  final ticks = <double>[];
  // Guard against float drift creating a huge loop.
  for (var v = start; v <= max + step * 0.5 && ticks.length < 12; v += step) {
    if (v >= min - step * 0.05) ticks.add(v);
  }
  if (ticks.isEmpty) return [min, max];
  return ticks;
}

/// Compact single-line number for axis labels. Avoids the fl_chart default
/// that wrapped `329.7K` into `329.` + `7K` on a too-narrow Y axis.
String formatAxisNumber(double value) {
  final abs = value.abs();
  if (abs >= 1000000) {
    return '${_trimZeros(value / 1000000)}M';
  }
  if (abs >= 10000) {
    return '${_trimZeros(value / 1000)}k';
  }
  if (abs >= 1000) {
    return '${_trimZeros(value / 1000)}k';
  }
  if (abs >= 100 || value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  if (abs >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

String _trimZeros(double value) {
  final raw = value.abs() >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return raw.endsWith('.0') ? raw.substring(0, raw.length - 2) : raw;
}

String formatElapsed(double seconds) {
  if (!seconds.isFinite) return '--';
  final negative = seconds < 0;
  final total = seconds.abs().round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final body = h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  return negative ? '-$body' : body;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Project how fast a recording of [bytes] over [duration] would fill storage.
String storageProjection({required int bytes, required Duration? duration}) {
  if (bytes <= 0) return 'No samples stored yet.';
  final seconds = duration?.inSeconds ?? 0;
  if (seconds < 30) {
    return 'Full-resolution SQLite table on this phone (${formatBytes(bytes)} so far). '
        'Record longer to estimate an hourly rate.';
  }
  final bytesPerHour = bytes / seconds * 3600;
  final hoursTo1Gb = (1024 * 1024 * 1024) / bytesPerHour;
  final hoursLabel = hoursTo1Gb >= 10
      ? '${hoursTo1Gb.toStringAsFixed(0)} hours'
      : '${hoursTo1Gb.toStringAsFixed(1)} hours';
  return 'Full-resolution SQLite table (not compressed): ${formatBytes(bytes)} '
      'for this session, about ${formatBytes(bytesPerHour.round())}/hour. '
      'At this mix of signals, 1 GB is roughly $hoursLabel of recording.';
}
