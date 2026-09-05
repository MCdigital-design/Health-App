import 'package:fl_chart/fl_chart.dart';
import '../charts/chart_math.dart';

/// Snapped Y-axis range so Live and session charts share one interval.
class ChartAxisRange {
  final double min;
  final double max;
  final double interval;

  const ChartAxisRange({
    required this.min,
    required this.max,
    required this.interval,
  });
}

/// A single (timestamp, value) reading.
class TimedValue {
  final int timestampMs;
  final double value;
  const TimedValue(this.timestampMs, this.value);
}

/// Pre-defined chart timeframes. Larger windows aggregate raw samples into
/// buckets instead of plotting every point, so the chart stays fast and
/// readable regardless of the underlying sample rate (HR ~1 Hz, PPG up to
/// ~176 Hz in SDK mode).
enum ChartTimeframe {
  // Labels are the *visible window*, not the bucket size. Selecting "30s"
  // used to mean 10 minutes of data in 30-second buckets — the chip and
  // the "last 10m" header contradicted each other.
  realtime(Duration(seconds: 15), Duration.zero, 'Real-time'),
  s1(Duration(seconds: 30), Duration(seconds: 1), '30s'),
  s5(Duration(minutes: 2), Duration(seconds: 5), '2m'),
  s30(Duration(minutes: 10), Duration(seconds: 30), '10m'),
  m1(Duration(minutes: 30), Duration(minutes: 1), '30m'),
  m5(Duration(hours: 2), Duration(minutes: 5), '2h');

  final Duration window;
  final Duration bucket;
  final String label;

  const ChartTimeframe(this.window, this.bucket, this.label);
}

/// Time-bounded (not count-bounded) ring buffer of samples for one signal
/// (e.g. heart rate or a PPG channel).
///
/// Storing by time window rather than a fixed sample count is what makes a
/// timeframe selector possible: a "1 minute" view needs up to 60x more raw
/// PPG samples in scope than a "1 second" view, and a fixed-length list
/// can't serve both. Points older than [retention] are pruned automatically.
///
/// This also fixes a class of chart bugs where synthetic x-coordinates
/// (e.g. "current list length") stop advancing once a fixed-size list starts
/// evicting old entries — every plotted point here uses its real wall-clock
/// timestamp, so the x-axis is always monotonic and never collides.
class TimeSeriesBuffer {
  final Duration retention;
  final List<TimedValue> _points = [];

  TimeSeriesBuffer({this.retention = const Duration(minutes: 30)});

  int? _lastTimestampMs;
  int? get lastTimestampMs => _lastTimestampMs;

  double? _lastValue;
  double? get lastValue => _lastValue;

  bool get isEmpty => _points.isEmpty;

  void add(int timestampMs, double value) {
    _points.add(TimedValue(timestampMs, value));
    _lastTimestampMs = timestampMs;
    _lastValue = value;
    _pruneOlderThan(timestampMs - retention.inMilliseconds);
  }

  void _pruneOlderThan(int cutoffMs) {
    var i = 0;
    while (i < _points.length && _points[i].timestampMs < cutoffMs) {
      i++;
    }
    if (i > 0) {
      _points.removeRange(0, i);
    }
  }

  void clear() {
    _points.clear();
    _lastTimestampMs = null;
  }

  /// Returns chart-ready spots for [timeframe], anchored to [now] (defaults
  /// to the last recorded sample time so this is deterministic in tests).
  ///
  /// The x-axis is seconds-ago, always in the range
  /// `[-window.inSeconds, 0]`, so it is stable across rebuilds and never
  /// depends on how many points happen to be buffered.
  List<FlSpot> spotsForTimeframe(ChartTimeframe timeframe, {int? now}) {
    if (_points.isEmpty) return const [];
    final nowMs = now ?? _lastTimestampMs!;
    final cutoffMs = nowMs - timeframe.window.inMilliseconds;

    final inWindow = _points.where((p) => p.timestampMs >= cutoffMs).toList();
    if (inWindow.isEmpty) return const [];

    if (timeframe.bucket == Duration.zero) {
      return inWindow
          .map((p) => FlSpot((p.timestampMs - nowMs) / 1000.0, p.value))
          .toList();
    }

    final bucketMs = timeframe.bucket.inMilliseconds;
    final buckets = <int, List<double>>{};
    for (final p in inWindow) {
      final bucketIndex = (p.timestampMs / bucketMs).floor();
      buckets.putIfAbsent(bucketIndex, () => []).add(p.value);
    }
    final sortedKeys = buckets.keys.toList()..sort();
    return sortedKeys.map((key) {
      final values = buckets[key]!;
      final avg = values.reduce((a, b) => a + b) / values.length;
      final bucketCenterMs = key * bucketMs + bucketMs / 2;
      return FlSpot((bucketCenterMs - nowMs) / 1000.0, avg);
    }).toList();
  }

  /// Min/max of the currently visible window, padded then snapped to even
  /// ticks so the axis never appends the raw sample extreme.
  ChartAxisRange? yRangeForTimeframe(ChartTimeframe timeframe, {int? now}) {
    final spots = spotsForTimeframe(timeframe, now: now);
    if (spots.isEmpty) return null;
    var min = spots.first.y;
    var max = spots.first.y;
    for (final s in spots) {
      if (s.y < min) min = s.y;
      if (s.y > max) max = s.y;
    }
    if (min == max) {
      min -= 1;
      max += 1;
    }
    final padding = (max - min) * 0.15;
    final snapped = snapRangeToNiceTicks(min: min - padding, max: max + padding);
    return ChartAxisRange(
      min: snapped.min,
      max: snapped.max,
      interval: snapped.interval,
    );
  }
}
