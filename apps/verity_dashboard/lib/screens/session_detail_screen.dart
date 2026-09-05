import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recording_session.dart';
import '../models/sensor_sample.dart';
import '../storage/local_db.dart';

class SessionDetailScreen extends StatefulWidget {
  final RecordingSession session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<SensorSample> _samples = [];
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
    final samples = await db.getSamples(widget.session.id);
    final counts = await db.getSampleTypeCounts(widget.session.id);
    final bytes = await db.estimateSessionBytes(widget.session.id);
    if (!mounted) return;
    setState(() {
      _samples = samples;
      _counts = counts;
      _estimatedBytes = bytes;
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
        title: const Text('Delete session?'),
        content: const Text('This cannot be undone.'),
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

    final hrSpots = <FlSpot>[];
    for (var i = 0; i < _samples.length; i++) {
      final hr = _samples[i].hr;
      if (hr != null) hrSpots.add(FlSpot(i.toDouble(), hr.toDouble()));
    }
    final ppgSpots = <FlSpot>[];
    for (var i = 0; i < _samples.length; i++) {
      final ppg = _samples[i].ppg;
      if (ppg != null && ppg.isNotEmpty) ppgSpots.add(FlSpot(i.toDouble(), ppg.first.toDouble()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: [
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
                        Text('Estimated storage: ${_formatBytes(_estimatedBytes)}'),
                      ],
                    ),
                  ),
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
                        if (_counts.total > 0 && _counts.hr == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'This session has no HR samples — the heart rate stream was not '
                              'delivering data for its entire duration (most commonly because SDK '
                              'Mode was on the whole time, which disables HR on Verity Sense). '
                              'Other signal types were still captured. Check the Live tab for an '
                              'orange "Heart rate is not active" banner next time this happens — '
                              'the app now also retries automatically every 20s.',
                              style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _StaticChart(title: 'Heart Rate', color: Colors.redAccent, spots: hrSpots),
                const SizedBox(height: 16),
                _StaticChart(title: 'PPG (first channel)', color: Colors.blueAccent, spots: ppgSpots),
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

class _StaticChart extends StatelessWidget {
  final String title;
  final Color color;
  final List<FlSpot> spots;

  const _StaticChart({required this.title, required this.color, required this.spots});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: spots.isEmpty
                  ? const Center(child: Text('No data'))
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: color,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
