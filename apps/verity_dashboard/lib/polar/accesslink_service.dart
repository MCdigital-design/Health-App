import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/recording_session.dart';
import '../models/sensor_sample.dart';
import '../storage/local_db.dart';

/// Client for Polar's cloud API (AccessLink / Polar Flow), as distinct from
/// the on-device BLE SDK. This is how sessions that have already been
/// synced to Polar Flow (and cleared from the sensor's own memory) can
/// still be imported — the BLE SDK's `listExercises()` can only see data
/// still physically stored on the sensor.
///
/// Requires the user to register a free API client at
/// https://admin.polaraccesslink.com themselves; Polar does not allow
/// third-party apps to share one client ID. This cannot be done on the
/// user's behalf without their Polar account credentials.
///
/// Endpoints per Polar's published AccessLink v3 API
/// (https://www.polar.com/accesslink-api/):
///   Authorization: https://flow.polar.com/oauth2/authorization
///   Token:         https://polarremote.com/v2/oauth2/token
///   API base:      https://www.polaraccesslink.com/v3
class AccessLinkService {
  static const _authorizationUrl = 'https://flow.polar.com/oauth2/authorization';
  static const _tokenUrl = 'https://polarremote.com/v2/oauth2/token';
  static const _apiBase = 'https://www.polaraccesslink.com/v3';

  static const _kClientId = 'accesslink_client_id';
  static const _kClientSecret = 'accesslink_client_secret';
  static const _kRedirectUri = 'accesslink_redirect_uri';
  static const _kAccessToken = 'accesslink_access_token';
  static const _kUserId = 'accesslink_user_id';
  static const _kMemberId = 'accesslink_member_id';

  Future<void> saveClientConfig({
    required String clientId,
    required String clientSecret,
    required String redirectUri,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kClientId, clientId.trim());
    await prefs.setString(_kClientSecret, clientSecret.trim());
    await prefs.setString(_kRedirectUri, redirectUri.trim());
  }

  Future<Map<String, String>> loadClientConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'clientId': prefs.getString(_kClientId) ?? '',
      'clientSecret': prefs.getString(_kClientSecret) ?? '',
      'redirectUri': prefs.getString(_kRedirectUri) ?? '',
    };
  }

  Future<bool> isConfigured() async {
    final c = await loadClientConfig();
    return c['clientId']!.isNotEmpty && c['clientSecret']!.isNotEmpty && c['redirectUri']!.isNotEmpty;
  }

  Future<bool> isLinked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccessToken) != null;
  }

  Future<void> unlink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kUserId);
  }

  /// Opens the Polar authorization page in the device browser. The user
  /// signs in with their Polar account and approves access; Polar then
  /// redirects to the configured redirect URI with a `?code=...` query
  /// parameter. Since this app does not register a deep-link handler for
  /// arbitrary redirect URIs (those must be pre-registered with Polar and
  /// vary per user), the user copies that resulting URL back into the app
  /// (see [exchangeCodeForToken]) rather than relying on an automatic
  /// redirect capture.
  Future<bool> launchAuthorization() async {
    final config = await loadClientConfig();
    final uri = Uri.parse(_authorizationUrl).replace(queryParameters: {
      'response_type': 'code',
      'client_id': config['clientId'],
      'redirect_uri': config['redirectUri'],
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String? _extractCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.contains('://') && !trimmed.contains('?') && !trimmed.contains('=')) {
      // Looks like a bare code, not a URL.
      return trimmed;
    }
    try {
      final uri = Uri.parse(trimmed);
      return uri.queryParameters['code'];
    } catch (_) {
      return null;
    }
  }

  /// Exchanges an authorization code (or the full redirect URL containing
  /// one) for an access token, then registers this app's user with
  /// AccessLink if not already registered. Throws with a descriptive
  /// message on failure.
  Future<void> exchangeCodeForToken(String codeOrRedirectUrl) async {
    final config = await loadClientConfig();
    final code = _extractCode(codeOrRedirectUrl);
    if (code == null || code.isEmpty) {
      throw const FormatException(
        'Could not find an authorization code in that input. Paste the full '
        'redirect URL from the browser (including "?code=...") or just the code itself.',
      );
    }

    final basicAuth = base64Encode(utf8.encode('${config['clientId']}:${config['clientSecret']}'));
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: {
        'Authorization': 'Basic $basicAuth',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config['redirectUri'] ?? '',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Token exchange failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    if (accessToken == null) {
      throw Exception('Token response did not include an access_token: ${response.body}');
    }
    final userId = json['x_user_id']?.toString();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, accessToken);
    if (userId != null) {
      await prefs.setString(_kUserId, userId);
    }

    await _registerUserIfNeeded(accessToken);
  }

  Future<void> _registerUserIfNeeded(String accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    var memberId = prefs.getString(_kMemberId);
    memberId ??= const Uuid().v4();
    await prefs.setString(_kMemberId, memberId);

    final response = await http.post(
      Uri.parse('$_apiBase/users'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'member-id': memberId}),
    );

    // 200 = registered now, 409 = already registered previously — both fine.
    if (response.statusCode != 200 && response.statusCode != 409) {
      throw Exception('User registration failed (${response.statusCode}): ${response.body}');
    }
  }

  Future<String?> _accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccessToken);
  }

  /// Fetches exercises already uploaded to Polar Flow (last 30 days, per
  /// Polar's API limits) and imports any not already present locally,
  /// tagged with [SessionSource.polarFlow]. Returns the number of newly
  /// imported sessions.
  Future<int> importExercises({void Function(String status)? onStatus}) async {
    final token = await _accessToken();
    if (token == null) {
      throw StateError('Not connected to Polar Flow. Complete the authorization step first.');
    }

    onStatus?.call('Fetching exercise list from Polar Flow...');
    final response = await http.get(
      Uri.parse('$_apiBase/exercises?samples=true'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (response.statusCode == 401) {
      throw Exception('Polar Flow session expired. Reconnect in Settings.');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to list exercises (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    final exercises = (decoded is List)
        ? decoded
        : (decoded is Map && decoded['exercises'] is List)
            ? decoded['exercises'] as List
            : const [];

    var imported = 0;
    final db = LocalDb.instance;
    for (final raw in exercises) {
      final exercise = raw as Map<String, dynamic>;
      final externalId = (exercise['id'] ?? exercise['exercise-id'])?.toString();
      if (externalId == null) continue;
      final sessionId = 'polarflow:$externalId';

      if (await db.sessionExistsForExternalId(sessionId)) {
        continue;
      }

      onStatus?.call('Importing exercise $externalId...');
      final parsed = _parseExercise(sessionId, exercise);
      if (parsed == null) continue;

      await db.insertSession(parsed.$1);
      if (parsed.$2.isNotEmpty) {
        await db.insertSamples(sessionId, parsed.$2);
      }
      imported++;
    }
    return imported;
  }

  (RecordingSession, List<SensorSample>)? _parseExercise(
    String sessionId,
    Map<String, dynamic> exercise,
  ) {
    final startTimeStr = (exercise['start_time'] ?? exercise['start-time'])?.toString();
    final startTime = startTimeStr != null ? DateTime.tryParse(startTimeStr) : null;
    if (startTime == null) return null;
    final startMs = startTime.millisecondsSinceEpoch;

    final durationStr = exercise['duration']?.toString();
    final duration = durationStr != null ? _parseIso8601Duration(durationStr) : null;
    final endMs = duration != null ? startMs + duration.inMilliseconds : startMs;

    final sport = exercise['sport']?.toString() ?? 'Exercise';
    final heartRate = exercise['heart_rate'] ?? exercise['heart-rate'];
    final avgHr = heartRate is Map ? heartRate['average'] : null;

    final samples = <SensorSample>[];
    final sampleBlocks = exercise['samples'];
    if (sampleBlocks is List) {
      for (final block in sampleBlocks) {
        if (block is! Map) continue;
        final sampleType = (block['sample-type'] ?? block['sample_type'])?.toString();
        // Sample type "1" is heart rate per Polar's AccessLink schema.
        if (sampleType != '1') continue;
        final recordingRateSec = (block['recording-rate'] ?? block['recording_rate']) as int? ?? 5;
        final data = block['data']?.toString();
        if (data == null || data.isEmpty) continue;
        final values = data.split(',');
        for (var i = 0; i < values.length; i++) {
          final hr = int.tryParse(values[i].trim());
          if (hr == null) continue;
          samples.add(SensorSample(
            timestampMs: startMs + i * recordingRateSec * 1000,
            hr: hr,
          ));
        }
      }
    }

    final session = RecordingSession(
      id: sessionId,
      deviceId: exercise['device']?.toString() ?? 'polar_flow',
      name: avgHr != null ? '$sport (avg $avgHr bpm)' : sport,
      startTimeMs: startMs,
      endTimeMs: endMs,
      dataTypes: 'hr',
      sampleCount: samples.length,
      source: SessionSource.polarFlow,
    );
    return (session, samples);
  }

  /// Minimal ISO-8601 duration parser covering the "PTnHnMnS" subset Polar
  /// actually returns (e.g. "PT2H44M"). Not a general-purpose implementation.
  Duration _parseIso8601Duration(String input) {
    final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$').firstMatch(input);
    if (match == null) return Duration.zero;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = double.tryParse(match.group(3) ?? '0') ?? 0;
    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }
}
