import 'package:flutter/material.dart';

import '../ai/studio_signal.dart';
import '../ai/studio_spec.dart';
import '../charts/chart_math.dart';
import '../models/recording_session.dart';
import '../storage/local_db.dart';
import 'interactive_time_chart.dart';

class StudioDashboardPage extends StatelessWidget {
  final String title;
  final StudioDashboardSpec spec;

  const StudioDashboardPage({
    super.key,
    required this.title,
    required this.spec,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StudioDashboardView(spec: spec),
    );
  }
}

class StudioDashboardView extends StatelessWidget {
  final StudioDashboardSpec spec;
  final double chartHeight;

  const StudioDashboardView({
    super.key,
    required this.spec,
    this.chartHeight = 200,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final widget in spec.widgets) ...[
          _StudioWidgetCard(spec: widget, chartHeight: chartHeight),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StudioWidgetCard extends StatelessWidget {
  final StudioWidget spec;
  final double chartHeight;

  const _StudioWidgetCard({required this.spec, required this.chartHeight});

  @override
  Widget build(BuildContext context) {
    switch (spec.type) {
      case 'metric':
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  [
                    spec.value ?? '—',
                    if (spec.unit != null && spec.unit!.isNotEmpty) spec.unit!,
                  ].join(' '),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        );
      case 'note':
        return Card(
          child: ListTile(
            title: Text(spec.title),
            subtitle: Text(spec.text ?? ''),
          ),
        );
      case 'chart':
        return _StudioChartCard(spec: spec, height: chartHeight);
      default:
        return Card(
          child: ListTile(
            title: Text(spec.title),
            subtitle: Text(spec.text ?? spec.value ?? spec.type),
          ),
        );
    }
  }
}

class _StudioChartCard extends StatelessWidget {
  final StudioWidget spec;
  final double height;

  const _StudioChartCard({required this.spec, required this.height});

  @override
  Widget build(BuildContext context) {
    final signal = chartSignalFromName(spec.signal);
    if (signal == null) {
      return Card(
        child: ListTile(
          title: Text(spec.title),
          subtitle: Text('Unknown signal: ${spec.signal ?? 'none'}'),
        ),
      );
    }
    final style = signalStyle(signal);
    return FutureBuilder<(RecordingSession?, List<TimeValue>)>(
      future: _load(signal),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Card(
            child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          );
        }
        final session = snapshot.data?.$1;
        final points = snapshot.data?.$2 ?? const <TimeValue>[];
        return InteractiveTimeChart(
          title: spec.title,
          points: points,
          color: style.color,
          unit: spec.unit ?? style.unit,
          height: height,
          clockStartMs: session?.startTimeMs,
          emptyLabel: session == null
              ? 'No matching recording on this phone'
              : 'No ${signal.column.toUpperCase()} in this recording',
        );
      },
    );
  }

  Future<(RecordingSession?, List<TimeValue>)> _load(ChartSignal signal) async {
    final db = LocalDb.instance;
    RecordingSession? session;
    if (spec.sessionId != null && spec.sessionId!.isNotEmpty) {
      session = await db.getSession(spec.sessionId!);
    }
    session ??= (await db.getSessions()).firstOrNull;
    if (session == null) return (null, const <TimeValue>[]);
    final points = await db.getChartSeries(
      sessionId: session.id,
      signal: signal,
      sessionStartMs: session.startTimeMs,
    );
    return (session, points);
  }
}
