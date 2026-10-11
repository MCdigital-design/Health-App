import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verity_dashboard/polar/polar_repository.dart';
import 'package:verity_dashboard/screens/live_screen.dart';

/// No physical Polar sensor is required. This isolates button/lifecycle
/// behavior from the native SDK; hardware BLE remains a separate QA gate.
class FakeRecordingRepository extends PolarRepository {
  final StreamController<String> _connections = StreamController.broadcast();
  bool connected = true;
  bool recording = false;
  bool failStart = false;
  int starts = 0;
  int stops = 0;

  @override
  Stream<String> get connectionStateStream => _connections.stream;
  @override
  bool get isConnected => connected;
  @override
  String? get connectedDeviceId => connected ? 'TEST-DEVICE' : null;
  @override
  bool get isRecordingLocalSession => recording;
  @override
  bool get isHrActive => true;
  @override
  bool get isPpgActive => true;

  @override
  Future<void> startHrStreaming({bool silent = false}) async {}
  @override
  Future<void> startPpgStreaming({bool silent = false}) async {}

  @override
  Future<String> startLocalSession(String name, [String? dataTypes]) async {
    starts++;
    if (failStart) throw StateError('Simulated database write failure');
    recording = true;
    return 'fake-session-id';
  }

  @override
  Future<void> stopLocalSession() async {
    stops++;
    recording = false;
  }

  void disconnectSensor() {
    connected = false;
    _connections.add('disconnected:TEST-DEVICE');
  }

  @override
  void dispose() {
    _connections.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Stop stays enabled after BLE disconnect during recording', (tester) async {
    final repo = FakeRecordingRepository();
    await tester.pumpWidget(
      Provider<PolarRepository>.value(
        value: repo,
        child: const MaterialApp(home: LiveScreen()),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pump();
    expect(repo.starts, 1);
    expect(repo.recording, isTrue);

    repo.disconnectSensor();
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(repo.stops, 1);
    expect(repo.recording, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });

  testWidgets('failed database start shows error, not false Recording started', (tester) async {
    final repo = FakeRecordingRepository()..failStart = true;
    await tester.pumpWidget(
      Provider<PolarRepository>.value(
        value: repo,
        child: const MaterialApp(home: LiveScreen()),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pump();
    expect(repo.recording, isFalse);
    expect(find.textContaining('Recording failed'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
}
