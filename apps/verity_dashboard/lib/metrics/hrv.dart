import 'dart:math' as math;

import '../models/sensor_sample.dart';

/// Heart-rate variability from beat-to-beat intervals (RR / PPI, ms).
///
/// Polar Verity Sense exposes intervals two ways: `rrsMs` on each HR
/// packet, and a dedicated PPI stream (Polar's PPG-based algorithm).
/// Both land in [SensorSample.ppi]. RMSSD / SDNN / pNN50 are the usual
/// short-term HRV set — recovery and autonomic tone — and we compute
/// them here so the dashboard does not depend on a third-party service.
class HrvSummary {
  final int intervalCount;
  final double? rmssd;
  final double? sdnn;
  final double? pnn50;
  final double? meanRrMs;
  final int? meanHr;
  final int? minHr;
  final int? maxHr;

  const HrvSummary({
    required this.intervalCount,
    this.rmssd,
    this.sdnn,
    this.pnn50,
    this.meanRrMs,
    this.meanHr,
    this.minHr,
    this.maxHr,
  });

  static const empty = HrvSummary(intervalCount: 0);

  bool get hasHrv => rmssd != null;
}

/// Physiologically plausible RR window (ms). Drops Polar glitches.
const _minRrMs = 300;
const _maxRrMs = 2000;

List<int> extractRrIntervals(Iterable<SensorSample> samples) {
  final out = <int>[];
  for (final s in samples) {
    final intervals = s.ppi;
    if (intervals == null) continue;
    for (final rr in intervals) {
      if (rr >= _minRrMs && rr <= _maxRrMs) out.add(rr);
    }
  }
  return out;
}

HrvSummary computeHrv(Iterable<SensorSample> samples) {
  final hrs = <int>[
    for (final s in samples)
      if (s.hr != null && s.hr! > 0) s.hr!,
  ];
  final rr = extractRrIntervals(samples);
  int? meanHr;
  int? minHr;
  int? maxHr;
  if (hrs.isNotEmpty) {
    var sum = 0;
    var min = hrs.first;
    var max = hrs.first;
    for (final h in hrs) {
      sum += h;
      if (h < min) min = h;
      if (h > max) max = h;
    }
    meanHr = (sum / hrs.length).round();
    minHr = min;
    maxHr = max;
  }

  if (rr.length < 2) {
    return HrvSummary(
      intervalCount: rr.length,
      meanHr: meanHr,
      minHr: minHr,
      maxHr: maxHr,
    );
  }

  var rrSum = 0;
  for (final v in rr) {
    rrSum += v;
  }
  final meanRr = rrSum / rr.length;
  var varSum = 0.0;
  for (final v in rr) {
    final d = v - meanRr;
    varSum += d * d;
  }
  final sdnn = math.sqrt(varSum / (rr.length - 1));

  var diffSq = 0.0;
  var over50 = 0;
  for (var i = 1; i < rr.length; i++) {
    final diff = (rr[i] - rr[i - 1]).abs();
    diffSq += diff * diff;
    if (diff > 50) over50++;
  }
  final nDiff = rr.length - 1;
  final rmssd = math.sqrt(diffSq / nDiff);
  final pnn50 = over50 / nDiff * 100;

  return HrvSummary(
    intervalCount: rr.length,
    rmssd: rmssd,
    sdnn: sdnn,
    pnn50: pnn50,
    meanRrMs: meanRr,
    meanHr: meanHr,
    minHr: minHr,
    maxHr: maxHr,
  );
}
