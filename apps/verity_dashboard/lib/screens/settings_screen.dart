import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../polar/accesslink_service.dart';
import '../polar/polar_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final List<dynamic> _foundDevices = [];
  String? _connectedDeviceId;
  bool _sdkMode = false;
  bool _autoReconnect = false;
  bool _scanning = false;
  StreamSubscription? _deviceSub;
  StreamSubscription? _connSub;
  StreamSubscription? _sdkModeSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _statusSub;
  String? _statusMessage;

  final _accessLink = AccessLinkService();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _redirectUriController = TextEditingController(text: 'https://verity-dashboard.local/callback');
  final _codeController = TextEditingController();
  bool _polarFlowConfigured = false;
  bool _polarFlowLinked = false;
  bool _polarFlowBusy = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<PolarRepository>();
    _connectedDeviceId = repo.connectedDeviceId;
    _sdkMode = repo.isSdkModeOn;
    _autoReconnect = repo.autoReconnectEnabled;
    _deviceSub = repo.deviceFoundStream.listen((device) {
      if (!_foundDevices.any((d) => d.deviceId == device.deviceId)) {
        setState(() => _foundDevices.add(device));
      }
    });
    _connSub = repo.connectionStateStream.listen((state) {
      if (state.startsWith('connected:')) {
        setState(() {
          _connectedDeviceId = state.split(':')[1];
          _scanning = false;
        });
      } else if (state.startsWith('disconnected:')) {
        setState(() => _connectedDeviceId = null);
      }
    });
    _sdkModeSub = repo.sdkModeStream.listen((on) {
      setState(() => _sdkMode = on);
    });
    _errorSub = repo.errorStream.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );
    });
    _statusSub = repo.statusStream.listen((message) {
      if (!mounted) return;
      setState(() => _statusMessage = message);
    });
    _loadAccessLinkState();
  }

  Future<void> _loadAccessLinkState() async {
    final config = await _accessLink.loadClientConfig();
    final configured = await _accessLink.isConfigured();
    final linked = await _accessLink.isLinked();
    if (!mounted) return;
    setState(() {
      _clientIdController.text = config['clientId'] ?? '';
      _clientSecretController.text = config['clientSecret'] ?? '';
      if ((config['redirectUri'] ?? '').isNotEmpty) {
        _redirectUriController.text = config['redirectUri']!;
      }
      _polarFlowConfigured = configured;
      _polarFlowLinked = linked;
    });
  }

  Future<void> _saveAccessLinkConfig() async {
    await _accessLink.saveClientConfig(
      clientId: _clientIdController.text,
      clientSecret: _clientSecretController.text,
      redirectUri: _redirectUriController.text,
    );
    await _loadAccessLinkState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Polar Flow client saved')));
  }

  Future<void> _openAuthorization() async {
    setState(() => _polarFlowBusy = true);
    try {
      final ok = await _accessLink.launchAuthorization();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the browser')),
        );
      }
    } finally {
      if (mounted) setState(() => _polarFlowBusy = false);
    }
  }

  Future<void> _connectWithCode() async {
    setState(() => _polarFlowBusy = true);
    try {
      await _accessLink.exchangeCodeForToken(_codeController.text);
      await _loadAccessLinkState();
      _codeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connected to Polar Flow')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
    } finally {
      if (mounted) setState(() => _polarFlowBusy = false);
    }
  }

  Future<void> _disconnectPolarFlow() async {
    await _accessLink.unlink();
    await _loadAccessLinkState();
  }

  Future<void> _scan() async {
    final repo = context.read<PolarRepository>();
    await repo.requestPermissions();
    setState(() {
      _foundDevices.clear();
      _scanning = true;
    });
    repo.startScan();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _connect(String deviceId) async {
    final repo = context.read<PolarRepository>();
    await repo.connect(deviceId);
  }

  Future<void> _disconnect() async {
    final repo = context.read<PolarRepository>();
    await repo.disconnect();
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _connSub?.cancel();
    _sdkModeSub?.cancel();
    _errorSub?.cancel();
    _statusSub?.cancel();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _redirectUriController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PolarRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_statusMessage != null)
            Card(
              color: Colors.blueGrey.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.sync, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_statusMessage!, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ),
          if (_statusMessage != null) const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Device', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _connectedDeviceId != null ? 'Connected: $_connectedDeviceId' : 'Not connected',
                          style: TextStyle(
                            color: _connectedDeviceId != null ? Colors.greenAccent : null,
                          ),
                        ),
                      ),
                      if (_connectedDeviceId != null)
                        OutlinedButton(
                          onPressed: _disconnect,
                          child: const Text('Disconnect'),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _scanning ? null : _scan,
                        child: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Scan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_foundDevices.isEmpty && !_scanning)
                    const Text('No devices found yet. Tap Scan and keep the sensor nearby.'),
                  ..._foundDevices.map((d) {
                    final isThisConnected = _connectedDeviceId == d.deviceId;
                    return ListTile(
                      title: Text(d.name),
                      subtitle: Text(d.deviceId),
                      trailing: isThisConnected
                          ? const Chip(label: Text('Connected'))
                          : ElevatedButton(
                              onPressed: () => _connect(d.deviceId),
                              child: const Text('Connect'),
                            ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                if (_sdkMode)
                  Container(
                    width: double.infinity,
                    color: Colors.red.withValues(alpha: 0.15),
                    padding: const EdgeInsets.all(12),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.redAccent, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SDK Mode disables Heart Rate and PPI on Verity Sense. Turn it off to see live BPM.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  title: const Text('SDK Mode'),
                  subtitle: const Text('Higher sample rates for PPG/ACC — disables HR/PPI'),
                  value: _sdkMode,
                  onChanged: _connectedDeviceId == null
                      ? null
                      : (v) async {
                          setState(() => _sdkMode = v);
                          await repo.enableSdkMode(v);
                        },
                ),
                SwitchListTile(
                  title: const Text('Auto Reconnect'),
                  subtitle: const Text('Reconnect automatically after a dropped connection or app restart'),
                  value: _autoReconnect,
                  onChanged: (v) async {
                    setState(() => _autoReconnect = v);
                    await repo.setAutoReconnect(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Polar Flow (optional)', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Icon(
                        _polarFlowLinked ? Icons.cloud_done : Icons.cloud_off,
                        color: _polarFlowLinked ? Colors.greenAccent : Colors.grey,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Imports exercises already uploaded to your Polar Flow account, including ones '
                    'no longer on the sensor itself. Requires your own free API client from '
                    'admin.polaraccesslink.com — this cannot be set up on your behalf, since it '
                    'needs your Polar account login.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _clientIdController,
                    decoration: const InputDecoration(labelText: 'Client ID', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _clientSecretController,
                    decoration: const InputDecoration(labelText: 'Client Secret', isDense: true),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _redirectUriController,
                    decoration: const InputDecoration(
                      labelText: 'Redirect URI (must match your client exactly)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton(onPressed: _saveAccessLinkConfig, child: const Text('Save')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _polarFlowConfigured && !_polarFlowBusy ? _openAuthorization : null,
                        child: const Text('Open Authorization Page'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'After approving in the browser, it will redirect to a URL that fails to load '
                    '(that\'s expected) — copy that full URL from the address bar and paste it below.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(labelText: 'Redirect URL or code', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _polarFlowConfigured && !_polarFlowBusy ? _connectWithCode : null,
                        child: _polarFlowBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Connect'),
                      ),
                      const SizedBox(width: 8),
                      if (_polarFlowLinked)
                        OutlinedButton(onPressed: _disconnectPolarFlow, child: const Text('Disconnect')),
                    ],
                  ),
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
                  Text('About', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Verity Dashboard v1.1.0'),
                  const Text('Offline-first Polar Verity Sense client'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
