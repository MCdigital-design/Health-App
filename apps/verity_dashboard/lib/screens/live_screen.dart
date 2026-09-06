import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/time_series_buffer.dart';
import '../polar/polar_errors.dart';
import '../polar/polar_repository.dart';
import '../widgets/heart_rate_ring.dart';
import '../widgets/live_chart.dart';

/// UI refresh cadence for the live charts. Decoupled from the underlying
/// sample rate (which can be 1 Hz for HR or up to ~176 Hz for PPG in SDK
/// mode) so the chart redraws smoothly instead of once per sample.
const _uiRefreshInterval = Duration(milliseconds: 500);

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  ChartTimeframe _timeframe = ChartTimeframe.realtime;

  int? _currentHr;
  int _battery = -1;
  String _connectionState = 'disconnected';
  bool _sdkModeOn = false;
  bool _hrActive = false;
  bool _recording = false;
  String? _statusMessage;

  Timer? _uiRefreshTimer;
  Timer? _statusClearTimer;
  StreamSubscription? _connSub;
  StreamSubscription? _batterySub;
  StreamSubscription? _errorSub;
  StreamSubscription? _sdkModeSub;
  StreamSubscription? _statusSub;

  late PolarRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = context.read<PolarRepository>();

    _connSub = _repo.connectionStateStream.listen((state) {
      setState(() => _connectionState = state);
    });
    _batterySub = _repo.batteryStream.listen((level) {
      setState(() => _battery = level);
    });
    _errorSub = _repo.errorStream.listen((message) {
      if (!mounted) return;
      if (isAlreadyInStateError(message)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    });
    _sdkModeSub = _repo.sdkModeStream.listen((on) {
      setState(() => _sdkModeOn = on);
    });
    _statusSub = _repo.statusStream.listen((message) {
      setState(() => _statusMessage = message);
      _statusClearTimer?.cancel();
      _statusClearTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _statusMessage = null);
      });
    });

    if (_repo.isConnected) {
      _sdkModeOn = _repo.isSdkModeOn;
      _connectionState = 'connected:${_repo.connectedDeviceId}';
      // Connect already auto-starts streams. Starting again issues another
      // REQUEST_MEASUREMENT_START and Polar answers ERROR_ALREADY_IN_STATE.
      if (!_repo.isHrActive) {
        _repo.startHrStreaming();
      }
      if (!_repo.isPpgActive) {
        _repo.startPpgStreaming();
      }
    }

    _uiRefreshTimer = Timer.periodic(_uiRefreshInterval, (_) => _refreshCharts());
  }

  void _refreshCharts() {
    if (!mounted) return;
    setState(() {
      _currentHr = _repo.hrBuffer.lastValue?.round();
      _hrActive = _repo.isHrActive;
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _repo.stopLocalSession();
      setState(() => _recording = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording saved. See it under Recordings > On Phone.')),
      );
    } else {
      await _repo.startLocalSession('Live Session');
      setState(() => _recording = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording started')),
      );
    }
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _statusClearTimer?.cancel();
    _connSub?.cancel();
    _batterySub?.cancel();
    _errorSub?.cancel();
    _sdkModeSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connectionState.startsWith('connected');
    final hrSpots = _repo.hrBuffer.spotsForTimeframe(_timeframe);
    final ppgSpots = _repo.ppgBuffer.spotsForTimeframe(_timeframe);
    final hrRange = _repo.hrBuffer.yRangeForTimeframe(_timeframe);
    final ppgRange = _repo.ppgBuffer.yRangeForTimeframe(_timeframe);

    final deviceId = _repo.connectedDeviceId;
    final deviceLabel = !connected
        ? 'Not connected'
        : [
            if (deviceId != null && deviceId.isNotEmpty) deviceId,
            if (_battery >= 0) '$_battery%',
          ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live'),
            Text(
              deviceLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: connected ? _toggleRecording : null,
            icon: Icon(
              _recording ? Icons.stop_circle : Icons.fiber_manual_record,
              color: _recording ? Colors.redAccent : Colors.white,
            ),
            label: Text(
              _recording ? 'Stop' : 'Record',
              style: TextStyle(color: _recording ? Colors.redAccent : Colors.white),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshCharts(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!connected)
                _InfoBanner(
                  color: Colors.orange,
                  icon: Icons.warning_amber,
                  text: 'Not connected. Go to Settings to scan and connect your sensor.',
                ),
              if (connected && _sdkModeOn)
                _InfoBanner(
                  color: Colors.red,
                  icon: Icons.warning_amber,
                  text: 'SDK Mode is ON. Heart rate is disabled while it is on.',
                  action: TextButton(
                    onPressed: () => _repo.enableSdkMode(false),
                    child: const Text('Turn off'),
                  ),
                ),
              if (connected && !_sdkModeOn && !_hrActive)
                _InfoBanner(
                  color: Colors.orange,
                  icon: Icons.favorite_border,
                  text: 'Heart rate is not active right now. The app retries automatically, or tap Retry.',
                  action: TextButton(
                    onPressed: () => _repo.startHrStreaming(),
                    child: const Text('Retry'),
                  ),
                ),
              if (_statusMessage != null)
                _InfoBanner(
                  color: Colors.blueGrey,
                  icon: Icons.sync,
                  text: _statusMessage!,
                ),
              if (_recording)
                _InfoBanner(
                  color: Colors.red,
                  icon: Icons.fiber_manual_record,
                  text: 'Recording full-rate samples to this phone only — not Polar Flow, not GitHub.',
                ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      HeartRateRing(heartRate: _currentHr),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                                color: connected ? Colors.greenAccent : Colors.grey,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(_connectionState, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.battery_full, size: 18),
                              const SizedBox(width: 4),
                              Text(_battery >= 0 ? '$_battery%' : '--', style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _TimeframeSelector(
                value: _timeframe,
                onChanged: (tf) => setState(() => _timeframe = tf),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Window length on the chart — not the bucket size.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white54,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 700;
                  final hrChart = LiveChart(
                    spots: hrSpots,
                    title: 'Heart Rate',
                    unit: 'bpm',
                    color: Colors.redAccent,
                    timeframe: _timeframe,
                    yRange: hrRange,
                  );
                  final ppgChart = LiveChart(
                    spots: ppgSpots,
                    title: 'PPG Waveform',
                    color: Colors.blueAccent,
                    timeframe: _timeframe,
                    yRange: ppgRange,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: hrChart),
                        const SizedBox(width: 16),
                        Expanded(child: ppgChart),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      hrChart,
                      const SizedBox(height: 16),
                      ppgChart,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StreamChip(label: 'HR', active: _repo.isHrActive),
                  _StreamChip(label: 'PPG', active: _repo.isPpgActive),
                  _StreamChip(label: 'PPI', active: _repo.isPpiActive),
                  _StreamChip(label: 'Accel', active: _repo.isAccActive),
                  _StreamChip(label: 'Gyro', active: _repo.isGyroActive),
                  _StreamChip(label: 'Mag', active: _repo.isMagActive),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: connected ? () => _repo.startHrStreaming() : null,
                      icon: const Icon(Icons.favorite),
                      label: const Text('Start HR'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: connected ? () => _repo.startPpgStreaming() : null,
                      icon: const Icon(Icons.waves),
                      label: const Text('Start PPG'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeframeSelector extends StatelessWidget {
  final ChartTimeframe value;
  final ValueChanged<ChartTimeframe> onChanged;

  const _TimeframeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ChartTimeframe.values.map((tf) {
          final selected = tf == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tf.label),
              selected: selected,
              onSelected: (_) => onChanged(tf),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StreamChip extends StatelessWidget {
  final String label;
  final bool active;

  const _StreamChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: active ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
      label: Text('${active ? '●' : '○'} $label'),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  const _InfoBanner({required this.color, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: color.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
              if (action != null) action!,
            ],
          ),
        ),
      ),
    );
  }
}

