import 'dart:async';
import 'package:polar/polar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/recording_session.dart';
import '../models/sensor_sample.dart';
import '../models/time_series_buffer.dart';
import '../storage/local_db.dart';

/// Thrown when a Polar SDK feature does not become ready in time, e.g.
/// because SDK Mode is disabling it (Verity Sense disables HR/PPI in SDK Mode).
class PolarFeatureTimeoutException implements Exception {
  final String message;
  PolarFeatureTimeoutException(this.message);
  @override
  String toString() => message;
}

const _prefAutoReconnect = 'autoReconnect';
const _prefLastDeviceId = 'lastDeviceId';
const _prefRecordAccel = 'recordAccelerometer';
const _prefRecordGyro = 'recordGyroscope';
const _prefRecordMag = 'recordMagnetometer';

/// How long a stream can go without a new sample before it's considered
/// stalled and force-restarted. Set well above normal HR cadence (~1/s) and
/// PPG cadence (tens of Hz), but low enough that a real BLE stall is caught
/// and self-healed within seconds rather than leaving a dead flat line.
const _staleThreshold = Duration(seconds: 12);
const _watchdogInterval = Duration(seconds: 5);

/// How often to retry starting a stream that *should* be running (SDK Mode
/// off, connected) but isn't currently active — covering the case where the
/// very first start attempt failed and nothing ever tried again, not just
/// the case where a previously-healthy stream went stale.
const _startRetryInterval = Duration(seconds: 20);

class PolarRepository {
  final Polar _polar = Polar();
  final LocalDb _db = LocalDb.instance;
  final Uuid _uuid = const Uuid();

  final StreamController<PolarDeviceInfo> _deviceFoundController = StreamController.broadcast();
  final StreamController<String> _connectionStateController = StreamController.broadcast();
  final StreamController<SensorSample> _liveSampleController = StreamController.broadcast();
  final StreamController<int> _batteryController = StreamController.broadcast();
  final StreamController<String> _errorController = StreamController.broadcast();
  final StreamController<String> _statusController = StreamController.broadcast();
  final StreamController<bool> _sdkModeController = StreamController.broadcast();
  final StreamController<void> _sessionsChangedController = StreamController.broadcast();

  Stream<PolarDeviceInfo> get deviceFoundStream => _deviceFoundController.stream;
  Stream<String> get connectionStateStream => _connectionStateController.stream;
  Stream<SensorSample> get liveSampleStream => _liveSampleController.stream;
  Stream<int> get batteryStream => _batteryController.stream;

  /// User-facing errors (shown as SnackBars).
  Stream<String> get errorStream => _errorController.stream;

  /// Transient, non-error status updates (e.g. "reconnecting..."), meant for
  /// a subtler UI treatment than errorStream.
  Stream<String> get statusStream => _statusController.stream;

  Stream<bool> get sdkModeStream => _sdkModeController.stream;

  /// Fires whenever recorded session data changes (new session started or
  /// finalized, an exercise synced, an import completed, a session
  /// deleted) so any screen showing session lists/history can refresh
  /// without relying on being freshly mounted.
  Stream<void> get sessionsChanged => _sessionsChangedController.stream;

  /// Live rolling buffers, keyed by real timestamps (not sample-count
  /// indices), shared by any screen that wants to chart them. See
  /// [TimeSeriesBuffer] for why this matters for correctness.
  final TimeSeriesBuffer hrBuffer = TimeSeriesBuffer(retention: const Duration(minutes: 30));
  final TimeSeriesBuffer ppgBuffer = TimeSeriesBuffer(retention: const Duration(minutes: 5));

  String? _connectedDeviceId;
  String? get connectedDeviceId => _connectedDeviceId;
  bool get isConnected => _connectedDeviceId != null;

  bool _sdkModeEnabled = false;
  bool get isSdkModeOn => _sdkModeEnabled;

  bool _autoReconnectEnabled = false;
  bool get autoReconnectEnabled => _autoReconnectEnabled;
  String? _lastDeviceId;
  String? get lastDeviceId => _lastDeviceId;

  bool _userInitiatedDisconnect = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;

  // Tracks which sdkFeatureReady events have already fired per device, since
  // that event is only emitted once and a late subscriber (e.g. a screen
  // opened after connecting) would otherwise wait forever for an event that
  // already happened.
  final Map<String, Set<PolarSdkFeature>> _readyFeatures = {};

  bool _hrStreaming = false;
  bool _ppgStreaming = false;
  bool _accStreaming = false;
  bool _gyroStreaming = false;
  bool _magStreaming = false;
  bool _ppiStreaming = false;

  bool get isHrActive => _hrStreaming;
  bool get isPpgActive => _ppgStreaming;
  bool get isAccActive => _accStreaming;
  bool get isGyroActive => _gyroStreaming;
  bool get isMagActive => _magStreaming;

  bool _recordAccel = true;
  bool _recordGyro = false;
  bool _recordMag = false;
  bool get recordAccel => _recordAccel;
  bool get recordGyro => _recordGyro;
  bool get recordMag => _recordMag;

  bool _gyroUnsupported = false;
  bool _magUnsupported = false;

  bool _hrStartInProgress = false;
  bool _ppgStartInProgress = false;
  int? _lastHrStartAttemptMs;
  int? _lastPpgStartAttemptMs;

  StreamSubscription? _hrSub;
  StreamSubscription? _ppgSub;
  StreamSubscription? _accSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _magSub;
  StreamSubscription? _ppiSub;

  String? _currentSessionId;
  final List<SensorSample> _sessionBuffer = [];
  Timer? _flushTimer;

  PolarRepository() {
    _loadPrefs();

    _polar.sdkFeatureReady.listen((event) {
      _readyFeatures.putIfAbsent(event.identifier, () => {}).add(event.feature);
    });

    _polar.deviceConnected.listen((device) async {
      _connectedDeviceId = device.deviceId;
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _connectionStateController.add('connected:${device.deviceId}');
      _rememberDevice(device.deviceId);
      _startWatchdog();

      var sdkOn = false;
      try {
        sdkOn = await _polar.isSdkModeEnabled(device.deviceId);
      } catch (_) {
        // Older firmware may not support the query; assume off.
      }
      _sdkModeEnabled = sdkOn;
      _sdkModeController.add(sdkOn);

      // Auto-start both streams immediately on connect so live data shows
      // up without requiring a manual tap. HR is skipped when SDK Mode is
      // on, since Verity Sense does not support HR in that mode.
      if (!sdkOn) {
        unawaited(startHrStreaming());
      }
      unawaited(startPpgStreaming());
      unawaited(startEnabledMotionStreams(silent: true));
    });

    _polar.deviceConnecting.listen((device) {
      _connectionStateController.add('connecting:${device.deviceId}');
    });

    _polar.deviceDisconnected.listen((event) {
      if (_connectedDeviceId == event.info.deviceId) {
        _connectedDeviceId = null;
      }
    _readyFeatures.remove(event.info.deviceId);
    _gyroUnsupported = false;
    _magUnsupported = false;
    _cancelAllStreamSubs();
      _stopWatchdog();
      _connectionStateController.add('disconnected:${event.info.deviceId}');

      if (!_userInitiatedDisconnect && _autoReconnectEnabled) {
        _scheduleReconnect(event.info.deviceId);
      }
      _userInitiatedDisconnect = false;
    });

    _polar.batteryLevel.listen((event) {
      _batteryController.add(event.level);
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _autoReconnectEnabled = prefs.getBool(_prefAutoReconnect) ?? false;
    _lastDeviceId = prefs.getString(_prefLastDeviceId);
    _recordAccel = prefs.getBool(_prefRecordAccel) ?? true;
    _recordGyro = prefs.getBool(_prefRecordGyro) ?? false;
    _recordMag = prefs.getBool(_prefRecordMag) ?? false;
  }

  Future<void> setRecordAccel(bool value) async {
    _recordAccel = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRecordAccel, value);
    if (isConnected) {
      if (value) {
        await startAccStreaming(silent: true);
      } else {
        await _accSub?.cancel();
        _accStreaming = false;
      }
    }
  }

  Future<void> setRecordGyro(bool value) async {
    _recordGyro = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRecordGyro, value);
    if (isConnected) {
      if (value) {
        await startGyroStreaming(silent: true);
      } else {
        await _gyroSub?.cancel();
        _gyroStreaming = false;
      }
    }
  }

  Future<void> setRecordMag(bool value) async {
    _recordMag = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRecordMag, value);
    if (isConnected) {
      if (value) {
        await startMagnetometerStreaming(silent: true);
      } else {
        await _magSub?.cancel();
        _magStreaming = false;
      }
    }
  }

  Future<void> startEnabledMotionStreams({bool silent = false}) async {
    if (_recordAccel) unawaited(startAccStreaming(silent: silent));
    if (_recordGyro) unawaited(startGyroStreaming(silent: silent));
    if (_recordMag) unawaited(startMagnetometerStreaming(silent: silent));
  }

  String get activeRecordingTypes {
    final types = <String>['hr', 'ppg'];
    if (_accStreaming) types.add('acc');
    if (_gyroStreaming) types.add('gyro');
    if (_magStreaming) types.add('mag');
    return types.join(',');
  }

  Future<void> setAutoReconnect(bool value) async {
    _autoReconnectEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoReconnect, value);
  }

  Future<void> _rememberDevice(String deviceId) async {
    _lastDeviceId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastDeviceId, deviceId);
  }

  /// Attempts to reconnect to the last-known device on app start, if the
  /// user has Auto Reconnect enabled. Safe to call even if there is no
  /// remembered device or the setting is off (no-op).
  Future<void> tryAutoReconnectOnLaunch() async {
    await _loadPrefs();
    if (_autoReconnectEnabled && _lastDeviceId != null && !isConnected) {
      _statusController.add('Auto-reconnecting to last device...');
      try {
        await _polar.connectToDevice(_lastDeviceId!);
      } catch (e) {
        _errorController.add('Auto-reconnect failed: $e');
      }
    }
  }

  void _scheduleReconnect(String deviceId) {
    _reconnectTimer?.cancel();
    if (_reconnectAttempt >= 5) {
      _errorController.add('Lost connection to sensor and could not reconnect automatically. Reconnect manually from Settings.');
      return;
    }
    final delaySeconds = [3, 6, 12, 20, 30][_reconnectAttempt.clamp(0, 4)];
    _reconnectAttempt++;
    _statusController.add('Connection lost. Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempt/5)...');
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (isConnected) return;
      try {
        await _polar.connectToDevice(deviceId);
      } catch (e) {
        _scheduleReconnect(deviceId);
      }
    });
  }

  /// Call when the app returns to the foreground (e.g. after being
  /// backgrounded or the screen was locked). Immediately checks for and
  /// recovers from stalled streams instead of waiting for the next
  /// scheduled watchdog tick, and kicks a reconnect attempt if we dropped
  /// the connection while backgrounded.
  void onAppResumed() {
    if (!isConnected) {
      if (_autoReconnectEnabled && _lastDeviceId != null) {
        _scheduleReconnect(_lastDeviceId!);
      }
      return;
    }
    _checkStreamHealth();
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) => _checkStreamHealth());
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  void _checkStreamHealth() {
    if (_connectedDeviceId == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (_hrStreaming) {
      final last = hrBuffer.lastTimestampMs;
      if (!_sdkModeEnabled && last != null && nowMs - last > _staleThreshold.inMilliseconds) {
        _statusController.add('Heart rate stream stalled — restarting...');
        _hrSub?.cancel();
        _hrStreaming = false;
        unawaited(startHrStreaming(silent: true));
      }
    } else if (!_sdkModeEnabled && !_hrStartInProgress) {
      // HR should be running but isn't — either it never successfully
      // started (e.g. the very first attempt hit a transient failure) or
      // was stopped for some other reason. Keep retrying periodically
      // instead of requiring the user to notice and tap Start HR again;
      // this is what was missing when a single failed start left HR dead
      // for an entire recording with no automatic recovery.
      if (_lastHrStartAttemptMs == null || nowMs - _lastHrStartAttemptMs! > _startRetryInterval.inMilliseconds) {
        unawaited(startHrStreaming(silent: true));
      }
    }

    if (_ppgStreaming) {
      final last = ppgBuffer.lastTimestampMs;
      if (last != null && nowMs - last > _staleThreshold.inMilliseconds) {
        _statusController.add('PPG stream stalled — restarting...');
        _ppgSub?.cancel();
        _ppgStreaming = false;
        unawaited(startPpgStreaming(silent: true));
      }
    } else if (!_ppgStartInProgress) {
      if (_lastPpgStartAttemptMs == null || nowMs - _lastPpgStartAttemptMs! > _startRetryInterval.inMilliseconds) {
        unawaited(startPpgStreaming(silent: true));
      }
    }
  }

  void _cancelAllStreamSubs() {
    _hrSub?.cancel();
    _ppgSub?.cancel();
    _accSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _ppiSub?.cancel();
    _hrStreaming = false;
    _ppgStreaming = false;
    _accStreaming = false;
    _gyroStreaming = false;
    _magStreaming = false;
    _ppiStreaming = false;
  }

  Future<void> requestPermissions() async {
    await _polar.requestPermissions();
  }

  void startScan() {
    _polar.searchForDevice().listen((device) {
      _deviceFoundController.add(device);
    });
  }

  Future<void> connect(String deviceId) async {
    await _polar.connectToDevice(deviceId);
  }

  Future<void> disconnect() async {
    if (_connectedDeviceId != null) {
      _userInitiatedDisconnect = true;
      _reconnectTimer?.cancel();
      _reconnectAttempt = 0;
      await _polar.disconnectFromDevice(_connectedDeviceId!);
    }
  }

  Future<bool> refreshSdkModeState() async {
    if (_connectedDeviceId == null) return false;
    try {
      final v = await _polar.isSdkModeEnabled(_connectedDeviceId!);
      _sdkModeEnabled = v;
      _sdkModeController.add(v);
      return v;
    } catch (_) {
      return _sdkModeEnabled;
    }
  }

  /// Changes SDK Mode. Polar devices reject this change with an
  /// INVALID_STATE error while any online stream is active — this was
  /// previously unhandled, so a mode-change attempted while PPG was
  /// streaming (a very normal thing to do, since PPG auto-starts on
  /// connect) could silently fail on the device side while the app's UI
  /// still showed the toggle as changed, leaving HR permanently blocked
  /// for the rest of the session with no error shown.
  ///
  /// Now: stop all active streams first, attempt the change, then always
  /// re-query the device's actual state afterward instead of trusting the
  /// request succeeded, and restart whatever was running before.
  Future<void> enableSdkMode(bool enable) async {
    if (_connectedDeviceId == null) return;
    final deviceId = _connectedDeviceId!;

    final wasHr = _hrStreaming;
    final wasPpg = _ppgStreaming;
    final wasAcc = _accStreaming;
    final wasGyro = _gyroStreaming;
    final wasMag = _magStreaming;
    final wasPpi = _ppiStreaming;
    _cancelAllStreamSubs();
    // Give the native/BLE layer a moment to actually tear down the
    // streams before requesting a mode change that depends on nothing
    // being active.
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      if (enable) {
        await _polar.enableSdkMode(deviceId);
      } else {
        await _polar.disableSdkMode(deviceId);
      }
    } catch (e) {
      _errorController.add('Could not change SDK Mode: $e');
    }

    _gyroUnsupported = false;
    _magUnsupported = false;

    final actual = await refreshSdkModeState();
    if (actual != enable) {
      _errorController.add(
        'SDK Mode is still ${actual ? "on" : "off"} on the sensor (requested '
        '${enable ? "on" : "off"}). The device may have rejected the change. Try again.',
      );
    }

    if (wasHr && !actual) unawaited(startHrStreaming());
    if (wasPpg) unawaited(startPpgStreaming());
    if (wasAcc) unawaited(startAccStreaming());
    if (wasGyro) unawaited(startGyroStreaming());
    if (wasMag) unawaited(startMagnetometerStreaming());
    if (wasPpi) unawaited(startPpiStreaming());
  }

  /// Waits for [feature] to become ready on the connected device. Uses a
  /// cache so this returns immediately if the ready event already fired
  /// before this call started listening (e.g. right after connecting).
  Future<void> _waitForFeature(
    PolarSdkFeature feature, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deviceId = _connectedDeviceId;
    if (deviceId == null) {
      throw StateError('No device connected');
    }
    if (_readyFeatures[deviceId]?.contains(feature) == true) {
      return;
    }
    try {
      await _polar.sdkFeatureReady
          .firstWhere((e) => e.identifier == deviceId && e.feature == feature)
          .timeout(timeout);
    } on TimeoutException {
      final isHr = feature == PolarSdkFeature.hr;
      final hint = isHr && _sdkModeEnabled
          ? ' SDK Mode is enabled, which disables Heart Rate on Verity Sense. Turn off SDK Mode in Settings and try again.'
          : '';
      throw PolarFeatureTimeoutException(
        'Timed out waiting for ${feature.name} to become ready.$hint',
      );
    }
  }

  /// Starts HR streaming. [silent] routes failures to [statusStream]
  /// instead of [errorStream] — used for automatic background retries
  /// (watchdog, auto-start-on-connect) so a SnackBar doesn't pop up every
  /// 20 seconds while, say, SDK Mode is intentionally left on. Manual
  /// user-initiated calls (button taps) should leave this false.
  Future<void> startHrStreaming({bool silent = false}) async {
    if (_connectedDeviceId == null || _hrStreaming || _hrStartInProgress) return;
    _hrStartInProgress = true;
    _lastHrStartAttemptMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _waitForFeature(PolarSdkFeature.hr);
    } catch (e) {
      (silent ? _statusController : _errorController).add(e.toString());
      _hrStartInProgress = false;
      return;
    }
    final deviceId = _connectedDeviceId;
    if (deviceId == null) {
      _hrStartInProgress = false;
      return;
    }
    _hrStreaming = true;
    _hrStartInProgress = false;
    _hrSub = _polar.startHrStreaming(deviceId).listen(
      (data) {
        for (final sample in data.samples) {
          final tsMs = DateTime.now().millisecondsSinceEpoch;
          hrBuffer.add(tsMs, sample.hr.toDouble());
          final sensorSample = SensorSample(
            timestampMs: tsMs,
            hr: sample.hr,
            ppi: sample.rrsMs,
          );
          _liveSampleController.add(sensorSample);
          _addToSession(sensorSample);
        }
      },
      onError: (Object e) {
        _hrStreaming = false;
        _errorController.add('Heart rate stream error: $e');
      },
      onDone: () => _hrStreaming = false,
    );
  }

  Future<void> startPpgStreaming({bool silent = false}) async {
    if (_connectedDeviceId == null || _ppgStreaming || _ppgStartInProgress) return;
    _ppgStartInProgress = true;
    _lastPpgStartAttemptMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _waitForFeature(PolarSdkFeature.onlineStreaming);
    } catch (e) {
      (silent ? _statusController : _errorController).add(e.toString());
      _ppgStartInProgress = false;
      return;
    }
    final deviceId = _connectedDeviceId;
    if (deviceId == null) {
      _ppgStartInProgress = false;
      return;
    }
    _ppgStreaming = true;
    _ppgStartInProgress = false;
    _ppgSub = _polar.startPpgStreaming(deviceId).listen(
      (data) {
        for (final sample in data.samples) {
          final tsMs = sample.timeStamp.millisecondsSinceEpoch;
          if (sample.channelSamples.isNotEmpty) {
            ppgBuffer.add(tsMs, sample.channelSamples.first.toDouble());
          }
          final sensorSample = SensorSample(
            timestampMs: tsMs,
            ppg: sample.channelSamples,
          );
          _liveSampleController.add(sensorSample);
          _addToSession(sensorSample);
        }
      },
      onError: (Object e) {
        _ppgStreaming = false;
        _errorController.add('PPG stream error: $e');
      },
      onDone: () => _ppgStreaming = false,
    );
  }

  Future<void> startAccStreaming({bool silent = false}) async {
    if (_connectedDeviceId == null || _accStreaming) return;
    try {
      await _waitForFeature(PolarSdkFeature.onlineStreaming);
    } catch (e) {
      (silent ? _statusController : _errorController).add(e.toString());
      return;
    }
    final deviceId = _connectedDeviceId;
    if (deviceId == null) return;
    _accStreaming = true;
    _accSub = _polar.startAccStreaming(deviceId).listen(
      (data) {
        for (final sample in data.samples) {
          final sensorSample = SensorSample(
            timestampMs: sample.timeStamp.millisecondsSinceEpoch,
            acc: [sample.x.toDouble(), sample.y.toDouble(), sample.z.toDouble()],
          );
          _liveSampleController.add(sensorSample);
          _addToSession(sensorSample);
        }
      },
      onError: (Object e) {
        _accStreaming = false;
        (silent ? _statusController : _errorController).add(
          'Accelerometer stream error: $e',
        );
      },
      onDone: () => _accStreaming = false,
    );
  }

  Future<void> startGyroStreaming({bool silent = false}) async {
    if (_connectedDeviceId == null || _gyroStreaming || _gyroUnsupported) return;
    try {
      await _waitForFeature(PolarSdkFeature.onlineStreaming);
    } catch (e) {
      (silent ? _statusController : _errorController).add(e.toString());
      return;
    }
    final deviceId = _connectedDeviceId;
    if (deviceId == null) return;
    _gyroStreaming = true;
    _gyroSub = _polar.startGyroStreaming(deviceId).listen(
      (data) {
        for (final sample in data.samples) {
          final sensorSample = SensorSample(
            timestampMs: sample.timeStamp.millisecondsSinceEpoch,
            gyro: [sample.x.toDouble(), sample.y.toDouble(), sample.z.toDouble()],
          );
          _liveSampleController.add(sensorSample);
          _addToSession(sensorSample);
        }
      },
      onError: (Object e) {
        _gyroStreaming = false;
        _gyroUnsupported = true;
        (silent ? _statusController : _errorController).add(
          'Gyroscope is not available right now. On Verity Sense it usually '
          'needs SDK Mode, which turns off heart rate.',
        );
      },
      onDone: () => _gyroStreaming = false,
    );
  }

  Future<void> startMagnetometerStreaming({bool silent = false}) async {
    if (_connectedDeviceId == null || _magStreaming || _magUnsupported) return;
    try {
      await _waitForFeature(PolarSdkFeature.onlineStreaming);
    } catch (e) {
      (silent ? _statusController : _errorController).add(e.toString());
      return;
    }
    final deviceId = _connectedDeviceId;
    if (deviceId == null) return;
    _magStreaming = true;
    _magSub = _polar.startMagnetometerStreaming(deviceId).listen(
      (data) {
        for (final sample in data.samples) {
          final sensorSample = SensorSample(
            timestampMs: sample.timeStamp.millisecondsSinceEpoch,
            mag: [sample.x.toDouble(), sample.y.toDouble(), sample.z.toDouble()],
          );
          _liveSampleController.add(sensorSample);
          _addToSession(sensorSample);
        }
      },
      onError: (Object e) {
        _magStreaming = false;
        _magUnsupported = true;
        (silent ? _statusController : _errorController).add(
          'Magnetometer is not available on this sensor. Verity Sense often '
          'exposes only accelerometer (and gyro in SDK Mode).',
        );
      },
      onDone: () => _magStreaming = false,
    );
  }

  Future<void> startPpiStreaming() async {
    if (_connectedDeviceId == null || _ppiStreaming) return;
    try {
      await _waitForFeature(PolarSdkFeature.onlineStreaming);
    } catch (e) {
      _errorController.add(e.toString());
      return;
    }
    final deviceId = _connectedDeviceId;
    if (deviceId == null) return;
    _ppiStreaming = true;
    _ppiSub = _polar.startPpiStreaming(deviceId).listen(
      (data) {
        for (final sample in data.samples) {
          final sensorSample = SensorSample(
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            ppi: [sample.ppi],
          );
          _liveSampleController.add(sensorSample);
          _addToSession(sensorSample);
        }
      },
      onError: (Object e) {
        _ppiStreaming = false;
        _errorController.add('PPI stream error: $e');
      },
      onDone: () => _ppiStreaming = false,
    );
  }

  Future<String> startLocalSession(String name, [String? dataTypes]) async {
    await startEnabledMotionStreams(silent: true);
    final sessionId = _uuid.v4();
    final session = RecordingSession(
      id: sessionId,
      deviceId: _connectedDeviceId ?? 'unknown',
      name: name,
      startTimeMs: DateTime.now().millisecondsSinceEpoch,
      dataTypes: dataTypes ?? activeRecordingTypes,
      source: SessionSource.liveApp,
    );
    await _db.insertSession(session);
    _currentSessionId = sessionId;
    _sessionBuffer.clear();
    _flushTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flushSessionBuffer());
    _sessionsChangedController.add(null);
    return sessionId;
  }

  Future<void> stopLocalSession() async {
    _flushTimer?.cancel();
    await _flushSessionBuffer();
    if (_currentSessionId != null) {
      final count = await _db.getSampleCount(_currentSessionId!);
      await _db.updateSessionSampleCount(
        _currentSessionId!,
        count,
        endTimeMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
    _currentSessionId = null;
    _sessionsChangedController.add(null);
  }

  bool get isRecordingLocalSession => _currentSessionId != null;

  void _addToSession(SensorSample sample) {
    if (_currentSessionId == null) return;
    _sessionBuffer.add(sample);
    if (_sessionBuffer.length >= 100) {
      _flushSessionBuffer();
    }
  }

  Future<void> _flushSessionBuffer() async {
    if (_currentSessionId == null || _sessionBuffer.isEmpty) return;
    final samples = List<SensorSample>.from(_sessionBuffer);
    _sessionBuffer.clear();
    await _db.insertSamples(_currentSessionId!, samples);
  }

  Future<void> deleteSession(String sessionId) async {
    await _db.deleteSession(sessionId);
    _sessionsChangedController.add(null);
  }

  Future<void> deleteAllSessions() async {
    await _db.deleteAllSessions();
    _sessionsChangedController.add(null);
  }

  Future<List<PolarExerciseEntry>> listExercises() async {
    if (_connectedDeviceId == null) return [];
    return _polar.listExercises(_connectedDeviceId!);
  }

  /// Imports an on-device exercise (recorded using the sensor's own
  /// button). Uses a deterministic session id derived from the exercise
  /// entry so re-syncing the same exercise updates rather than duplicates
  /// it.
  Future<String> syncExercise(PolarExerciseEntry entry) async {
    if (_connectedDeviceId == null) throw StateError('No device connected');
    final sessionId = 'device:$_connectedDeviceId:${entry.entryId}';

    final data = await _polar.fetchExercise(_connectedDeviceId!, entry);
    final samples = <SensorSample>[];
    final startMs = entry.date.millisecondsSinceEpoch;
    for (var i = 0; i < data.samples.length; i++) {
      samples.add(SensorSample(
        timestampMs: startMs + i * data.interval * 1000,
        hr: data.samples[i],
      ));
    }

    final session = RecordingSession(
      id: sessionId,
      deviceId: _connectedDeviceId!,
      name: 'Exercise ${entry.path}',
      startTimeMs: startMs,
      endTimeMs: samples.isNotEmpty ? samples.last.timestampMs : startMs,
      dataTypes: 'hr',
      sampleCount: samples.length,
      source: SessionSource.deviceExercise,
    );
    // Replace any prior import of the same exercise instead of duplicating.
    await _db.deleteSession(sessionId);
    await _db.insertSession(session);
    await _db.insertSamples(sessionId, samples);
    await _polar.removeExercise(_connectedDeviceId!, entry);
    _sessionsChangedController.add(null);
    return sessionId;
  }

  void dispose() {
    _flushTimer?.cancel();
    _watchdogTimer?.cancel();
    _reconnectTimer?.cancel();
    _cancelAllStreamSubs();
    _deviceFoundController.close();
    _connectionStateController.close();
    _liveSampleController.close();
    _batteryController.close();
    _errorController.close();
    _statusController.close();
    _sdkModeController.close();
    _sessionsChangedController.close();
    if (_connectedDeviceId != null) {
      _polar.disconnectFromDevice(_connectedDeviceId!);
    }
  }
}
