import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../charts/chart_math.dart';
import '../metrics/hrv.dart';
import '../models/recording_session.dart';
import '../models/sensor_sample.dart';
import '../storage/local_db.dart';
import '../widgets/collapsible_hint.dart';
import '../widgets/interactive_time_chart.dart';
import 'ai_screen.dart';

class SessionDetailScreen extends StatefulWidget {
  final RecordingSession session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<SensorSample> _samples = [];
  List<TimeValue> _hr = const [];
  List<TimeValue> _ppg = const [];
  List<TimeValue> _ppi = const [];
  List<TimeValue> _acc = const [];
  List<TimeValue> _gyro = const [];
  List<TimeValue> _mag = const [];
  HrvSummary _hrv = HrvSummary.empty;
  SessionSampleCounts _counts = SessionSampleCounts.empty;
  int _estimatedBytes = 0;
  bool _loading = true;
  String? _exportedPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = LocalDb.instance;
    final session = widget.session;
    final results = await Future.wait([
      db.getSamples(session.id),
      db.getSampleTypeCounts(session.id),
      db.estimateSessionBytes(session.id),
      db.getChartSeries(sessionId: session.id, signal: ChartSignal.hr, sessionStartMs: session.startTimeMs),
      db.getChartSeries(sessionId: session.id, signal: ChartSignal.ppg, sessionStartMs: session.startTimeMs),
      db.getChartSeries(sessionId: session.id, signal: ChartSignal.ppi, sessionStartMs: session.startTimeMs),
      db.getChartSeries(sessionId: session.id, signal: ChartSignal.acc, sessionStartMs: session.startTimeMs),
      db.getChartSeries(sessionId: session.id, signal: ChartSignal.gyro, sessionStartMs: session.startTimeMs),
      db.getChartSeries(sessionId: session.id, signal: ChartSignal.mag, sessionStartMs: session.startTimeMs),
    ]);
    if (!mounted) return;
    final samples = results[0] as List<SensorSample>;
    setState(() {
      _samples = samples;
      _counts = results[1] as SessionSampleCounts;
      _estimatedBytes = results[2] as int;
      _hr = results[3] as List<TimeValue>;
      _ppg = results[4] as List<TimeValue>;
      _ppi = results[5] as List<TimeValue>;
      _acc = results[6] as List<TimeValue>;
      _gyro = results[7] as List<TimeValue>;
      _mag = results[8] as List<TimeValue>;
      _hrv = computeHrv(samples);
      _loading = false;
    });
  }

  Future<void> _export() async {
    final buffer = StringBuffer();
    buffer.writeln('timestamp_ms,timestamp_iso,hr,ppi,ppg,acc,gyro,mag');
    for (final s in _samples) {
      final iso = DateTime.fromMillisecondsSinceEpoch(s.timestampMs).toIso8601String();
      buffer.writeln(
        '${s.timestampMs},$iso,${s.hr ?? ''},'
        '"${s.ppi?.join(';') ?? ''}","${s.ppg?.join(';') ?? ''}",'
        '"${s.acc?.join(';') ?? ''}","${s.gyro?.join(';') ?? ''}","${s.mag?.join(';') ?? ''}"',
      );
    }
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final safeName = widget.session.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}/verity_$safeName.csv');
      await file.writeAsString(buffer.toString());
      setState(() => _exportedPath = file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ${file.path}'), duration: const Duration(seconds: 6)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this session from the phone?'),
        content: Text(
          'Removes ${formatBytes(_estimatedBytes)} of full-resolution samples '
          'from this phone only. Polar Flow and the official Polar app are not '
          'changed. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalDb.instance.deleteSession(widget.session.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final dateFmt = DateFormat('MMM d, yyyy HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Ask AI about this session',
            onPressed: _loading
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AiScreen(focusSession: session),
                      ),
                    );
                  },
          ),
          IconButton(icon: const Icon(Icons.ios_share), onPressed: _loading ? null : _export),
          IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Chip(label: Text(session.source.label)),
                            const SizedBox(width: 8),
                            if (session.duration != null)
                              Chip(label: Text(_formatDuration(session.duration!))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Started: ${dateFmt.format(DateTime.fromMillisecondsSinceEpoch(session.startTimeMs))}'),
                        Text('Device: ${session.deviceId}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _StorageCard(
                  bytes: _estimatedBytes,
                  duration: session.duration,
                  totalSamples: _counts.total,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sample breakdown', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _CountChip(label: 'Total', count: _counts.total),
                            _CountChip(label: 'HR', count: _counts.hr),
                            _CountChip(label: 'PPG', count: _counts.ppg),
                            _CountChip(label: 'PPI', count: _counts.ppi),
                            _CountChip(label: 'Accel', count: _counts.acc),
                            _CountChip(label: 'Gyro', count: _counts.gyro),
                            _CountChip(label: 'Mag', count: _counts.mag),
                          ],
                        ),
                        if (_counts.ppg == 0 && _counts.hr > 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'No PPG in this take — that is why a longer session can be '
                              'much smaller than a shorter one.',
                              style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                            ),
                          ),
                        if (_counts.acc == 0 && _counts.gyro == 0 && _counts.mag == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'No motion samples. New recordings start accel / gyro / mag '
                              'from Settings → Motion sensors.',
                              style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                            ),
                          ),
                        if (_counts.total > 0 && _counts.hr == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'No HR samples. SDK Mode on Verity Sense disables heart rate.',
                              style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                            ),
                          ),
                        const CollapsibleHint(
                          label: 'Why row counts differ',
                          body:
                              'Nothing is compressed. Each number is a full stored row.\n\n'
                              'Heart rate is about 1 row per second, so 25 minutes is ~1,500 '
                              'rows and tens of KB. PPG is about 40 rows per second, so 16 '
                              'minutes is ~40,000 rows and ~1.7 MB. Motion at 52 Hz is similar '
                              'to PPG. A short take with PPG is always larger than a long take '
                              'with only HR/PPI.',
                        ),
                        if (_counts.acc == 0 && _counts.gyro == 0 && _counts.mag == 0)
                          const CollapsibleHint(
                            label: 'Why motion is zero',
                            body:
                                'Older takes never asked the sensor for accelerometer, '
                                'gyroscope, or magnetometer. New recordings request those '
                                'together with HR and PPG. Polar documents those six online '
                                'streams on Verity Sense. SDK Mode is left off so heart rate '
                                'stays on.',
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const _PrivacyCard(),
                const SizedBox(height: 16),
                _HrvCard(hrv: _hrv),
                const SizedBox(height: 16),
                InteractiveTimeChart(
                  title: 'Heart Rate',
                  unit: 'bpm',
                  color: Colors.redAccent,
                  points: _hr,
                  clockStartMs: session.startTimeMs,
                  emptyLabel: _counts.hr == 0
                      ? 'No heart-rate samples in this recording'
                      : 'Heart-rate samples could not be plotted',
                ),
                const SizedBox(height: 16),
                InteractiveTimeChart(
                  title: 'PPG',
                  color: Colors.blueAccent,
                  points: _ppg,
                  clockStartMs: session.startTimeMs,
                  emptyLabel: 'No PPG samples in this recording',
                ),
                if (_ppi.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InteractiveTimeChart(
                    title: 'Beat interval',
                    unit: 'ms',
                    color: Colors.lightGreenAccent,
                    points: _ppi,
                    clockStartMs: session.startTimeMs,
                  ),
                ],
                if (_acc.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InteractiveTimeChart(
                    title: 'Accelerometer',
                    unit: 'mg',
                    color: Colors.tealAccent,
                    points: _acc,
                    clockStartMs: session.startTimeMs,
                  ),
                ],
                if (_gyro.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InteractiveTimeChart(
                    title: 'Gyroscope',
                    color: Colors.amberAccent,
                    points: _gyro,
                    clockStartMs: session.startTimeMs,
                  ),
                ],
                if (_mag.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InteractiveTimeChart(
                    title: 'Magnetometer',
                    color: Colors.purpleAccent,
                    points: _mag,
                    clockStartMs: session.startTimeMs,
                  ),
                ],
                if (_exportedPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SelectableText(
                      'Exported to:\n$_exportedPath',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  final int bytes;
  final Duration? duration;
  final int totalSamples;

  const _StorageCard({
    required this.bytes,
    required this.duration,
    required this.totalSamples,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Storage on this phone', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${formatBytes(bytes)}  ·  $totalSamples full-size rows',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            CollapsibleHint(
              label: 'How storage works',
              body:
                  '${storageProjection(bytes: bytes, duration: duration)}\n\n'
                  'Delete this session with the trash icon, or clear every recording '
                  'under Settings. Uninstalling the app or clearing its Android storage '
                  'also removes the SQLite file.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where this data lives', style: Theme.of(context).textTheme.titleMedium),
            const CollapsibleHint(
              label: 'Phone only — not Polar Flow or GitHub',
              body:
                  'Live recordings in this app are one-way Bluetooth streams onto the '
                  'phone. They are not written back to the sensor, and they do not sync '
                  'to Polar Flow or the official Polar app. Sessions you record here will '
                  'not appear there.\n\n'
                  'The sensor only keeps its own button-press exercises (recording / '
                  'swimming mode). Those can sync to Polar Flow if the sensor is paired '
                  'with a Polar account — that is a separate pipeline.\n\n'
                  'This app does not upload health data to GitHub. A public repo is the '
                  'wrong place for heart-rate and PPG traces. Share a CSV yourself only '
                  'if you intend to.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HrvCard extends StatelessWidget {
  final HrvSummary hrv;

  const _HrvCard({required this.hrv});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Heart-rate variability', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MetricChip(label: 'RMSSD', value: _ms(hrv.rmssd)),
                _MetricChip(label: 'SDNN', value: _ms(hrv.sdnn)),
                _MetricChip(label: 'pNN50', value: hrv.pnn50 == null ? '—' : '${hrv.pnn50!.round()}%'),
                _MetricChip(label: 'Mean HR', value: hrv.meanHr == null ? '—' : '${hrv.meanHr}'),
                _MetricChip(label: 'Min / max', value: hrv.minHr == null ? '—' : '${hrv.minHr}–${hrv.maxHr}'),
                _MetricChip(label: 'Beats', value: '${hrv.intervalCount}'),
              ],
            ),
            if (hrv.intervalCount == 0)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No usable beat intervals. Polar often omits RR on optical HR; '
                  'RMSSD needs those intervals — BPM alone is not enough.',
                  style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                ),
              ),
            const CollapsibleHint(
              label: 'What HRV is',
              body:
                  'HRV is the change in time between beats. Polar Verity Sense '
                  'gives those intervals on the HR stream (and a dedicated PPI '
                  'stream while you Record). RMSSD is the usual recovery number; '
                  'we calculate it on the phone from stored beats — nothing extra '
                  'is sent to Polar or GitHub.',
            ),
          ],
        ),
      ),
    );
  }

  String _ms(double? value) => value == null ? '—' : '${value.round()} ms';
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label  $value'));
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  const _CountChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: count > 0 ? null : Colors.white10,
      label: Text('$label: $count'),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
