import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ai/studio_dashboard_store.dart';
import '../metrics/hrv.dart';
import '../models/recording_session.dart';
import '../models/sensor_sample.dart';
import '../polar/polar_repository.dart';
import '../storage/local_db.dart';
import '../widgets/studio_dashboard_view.dart';
import 'session_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<RecordingSession> _sessions = [];
  Map<String, List<SensorSample>> _samples = {};
  List<SavedStudioDashboard> _custom = const [];
  StreamSubscription? _sessionsChangedSub;
  StreamSubscription? _studioSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    // See RecordingsScreen for why this subscription is required: tabs are
    // kept alive via IndexedStack and never rebuild on their own when data
    // changes elsewhere.
    _sessionsChangedSub = context.read<PolarRepository>().sessionsChanged.listen((_) {
      _loadData();
    });
    _studioSub = StudioDashboardStore.changes.listen((_) => _loadData());
  }

  @override
  void dispose() {
    _sessionsChangedSub?.cancel();
    _studioSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final sessions = await LocalDb.instance.getSessions();
    final samples = <String, List<SensorSample>>{};
    for (final s in sessions.take(20)) {
      samples[s.id] = await LocalDb.instance.getSamplesWithSignal(
        s.id,
        ChartSignal.hr,
        limit: 2000,
      );
    }
    final custom = await StudioDashboardStore().list();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _samples = samples;
      _custom = custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCards(),
            if (_custom.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Custom views', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._custom.map(_buildCustomCard),
            ],
            const SizedBox(height: 16),
            if (_sessions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No sessions yet. Record on the Live tab or sync/import on Recordings.'),
                ),
              )
            else
              ..._sessions.take(20).map((s) => _buildSessionCard(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final totalSessions = _sessions.length;
    final totalSamples = _sessions.fold<int>(0, (sum, s) => sum + s.sampleCount);

    final allHr = <int>[];
    for (final list in _samples.values) {
      for (final s in list) {
        if (s.hr != null) allHr.add(s.hr!);
      }
    }
    final avgHr = allHr.isEmpty ? null : (allHr.reduce((a, b) => a + b) / allHr.length).round();
    final allSamples = _samples.values.expand((list) => list);
    final hrv = computeHrv(allSamples);

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SummaryCard(title: 'Sessions', value: '$totalSessions', icon: Icons.folder)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Samples', value: '$totalSamples', icon: Icons.data_usage)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Avg HR', value: avgHr != null ? '$avgHr' : '--', icon: Icons.favorite)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'RMSSD',
                value: hrv.rmssd == null ? '--' : '${hrv.rmssd!.round()}',
                icon: Icons.monitor_heart,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'SDNN',
                value: hrv.sdnn == null ? '--' : '${hrv.sdnn!.round()}',
                icon: Icons.timeline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'pNN50',
                value: hrv.pnn50 == null ? '--' : '${hrv.pnn50!.round()}%',
                icon: Icons.percent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomCard(SavedStudioDashboard row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.dashboard_customize),
        title: Text(row.title),
        subtitle: const Text('Built in AI Studio'),
        onTap: () {
          final spec = row.spec;
          if (spec == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StudioDashboardPage(title: row.title, spec: spec),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionCard(RecordingSession session) {
    final samples = _samples[session.id] ?? [];
    final hrSpots = <FlSpot>[];
    if (samples.isNotEmpty) {
      final origin = samples.first.timestampMs;
      for (final sample in samples) {
        if (sample.hr != null) {
          hrSpots.add(FlSpot((sample.timestampMs - origin) / 1000.0, sample.hr!.toDouble()));
        }
      }
    }
    final hasAnySamples = samples.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
          final deleted = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)),
          );
          if (deleted == true) _loadData();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(session.name, style: Theme.of(context).textTheme.titleMedium)),
                  Chip(
                    label: Text(session.source.label, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Text(
                DateTime.fromMillisecondsSinceEpoch(session.startTimeMs).toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: hrSpots.isEmpty
                    ? Center(
                        child: Text(
                          hasAnySamples ? 'No HR data in this session (tap for breakdown)' : 'No data',
                        ),
                      )
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
                              spots: hrSpots,
                              isCurved: true,
                              color: Colors.redAccent,
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
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
