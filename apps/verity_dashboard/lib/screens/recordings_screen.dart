import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/recording_session.dart';
import '../charts/chart_math.dart';
import '../polar/accesslink_service.dart';
import '../polar/polar_repository.dart';
import '../storage/local_db.dart';
import 'session_detail_screen.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final _accessLink = AccessLinkService();
  List<RecordingSession> _sessions = [];
  Map<String, int> _sessionBytes = {};
  List<dynamic> _deviceExercises = [];
  bool _loading = false;
  bool _polarFlowLinked = false;
  StreamSubscription? _sessionsChangedSub;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _refreshPolarFlowStatus();
    // This is the fix for sessions "disappearing": the app keeps every tab
    // alive (IndexedStack), so without this subscription this screen would
    // only ever load data once, at app startup, and never notice a new
    // recording finished on the Live tab.
    _sessionsChangedSub = context.read<PolarRepository>().sessionsChanged.listen((_) {
      _loadSessions();
    });
  }

  @override
  void dispose() {
    _sessionsChangedSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshPolarFlowStatus() async {
    final linked = await _accessLink.isLinked();
    if (mounted) setState(() => _polarFlowLinked = linked);
  }

  Future<void> _loadSessions() async {
    final sessions = await LocalDb.instance.getSessions();
    final bytes = await LocalDb.instance.estimateAllSessionBytes();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _sessionBytes = bytes;
      });
    }
  }

  Future<void> _scanDeviceExercises() async {
    final repo = context.read<PolarRepository>();
    setState(() => _loading = true);
    try {
      final exercises = await repo.listExercises();
      if (!mounted) return;
      setState(() => _deviceExercises = exercises);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadSessions(), _scanDeviceExercises(), _refreshPolarFlowStatus()]);
  }

  Future<void> _syncExercise(dynamic entry) async {
    final repo = context.read<PolarRepository>();
    setState(() => _loading = true);
    try {
      await repo.syncExercise(entry);
      await _scanDeviceExercises();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synced to phone')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importFromPolarFlow() async {
    setState(() => _loading = true);
    try {
      final count = await _accessLink.importExercises(
        onStatus: (s) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s), duration: const Duration(seconds: 1)),
            );
          }
        },
      );
      await _loadSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(count > 0 ? 'Imported $count session(s) from Polar Flow' : 'No new sessions to import')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSession(RecordingSession session) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)),
    );
    if (deleted == true) {
      await _loadSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refreshAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('On Device (not yet synced)', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Training sessions recorded using the sensor\'s own button (recording or '
                    'swimming mode). This requires the sensor to be registered with a Polar '
                    'Flow account — a Polar Verity Sense limitation, not something this app '
                    'controls. Tap the download icon to pull one onto the phone.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_deviceExercises.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No unsynced exercises found on device. Tap refresh to scan.'),
                      ),
                    )
                  else
                    ..._deviceExercises.map((e) => Card(
                          child: ListTile(
                            title: Text(e.path),
                            subtitle: Text(e.date.toString()),
                            trailing: IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: () => _syncExercise(e),
                            ),
                          ),
                        )),
                  const SizedBox(height: 24),
                  Text('Polar Flow import', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Sessions already uploaded to your Polar Flow account (including ones no '
                    'longer stored on the sensor itself). Requires a one-time setup in Settings '
                    'using your own free Polar API client.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _polarFlowLinked ? Icons.cloud_done : Icons.cloud_off,
                            color: _polarFlowLinked ? Colors.greenAccent : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _polarFlowLinked
                                  ? 'Connected to Polar Flow'
                                  : 'Not connected. Set up in Settings > Polar Flow.',
                            ),
                          ),
                          if (_polarFlowLinked)
                            ElevatedButton(
                              onPressed: _importFromPolarFlow,
                              child: const Text('Import'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('All sessions on phone', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Live recordings stay on this phone only. They do not appear in Polar Flow '
                    'or the official Polar app. Tap a session for charts, storage, and delete.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_sessions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No sessions yet. Go to Live and tap Record, or sync/import above.'),
                      ),
                    )
                  else
                    ..._sessions.map((s) => Card(
                          child: ListTile(
                            onTap: () => _openSession(s),
                            title: Text(s.name),
                            subtitle: Text(
                              '${dateFmt.format(DateTime.fromMillisecondsSinceEpoch(s.startTimeMs))} • '
                              '${s.sampleCount} samples'
                              '${_sessionBytes[s.id] != null ? ' • ${formatBytes(_sessionBytes[s.id]!)}' : ''}',
                            ),
                            trailing: Chip(
                              label: Text(s.source.label, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
