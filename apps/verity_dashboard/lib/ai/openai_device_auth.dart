import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// OpenAI Codex public device-code client (same as Codex CLI).
/// Tokens stay on this phone. Backup of prefs is already denied.
const kOpenAiClientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
const kOpenAiIssuer = 'https://auth.openai.com';
const kOpenAiVerificationUrl = 'https://auth.openai.com/codex/device';
const kOpenAiRedirectUri = 'https://auth.openai.com/deviceauth/callback';

const _kAccess = 'openai_access_token';
const _kRefresh = 'openai_refresh_token';
const _kId = 'openai_id_token';
const _kExpires = 'openai_expires_at_ms';
const _kAccount = 'openai_account_id';
const _kEmail = 'openai_email';
const _kPlan = 'openai_plan';

class DeviceLoginPending {
  final String userCode;
  final String deviceAuthId;
  final String verificationUrl;
  final Duration interval;

  const DeviceLoginPending({
    required this.userCode,
    required this.deviceAuthId,
    this.verificationUrl = kOpenAiVerificationUrl,
    this.interval = const Duration(seconds: 5),
  });
}

class OpenAiSession {
  final String accessToken;
  final String refreshToken;
  final String? idToken;
  final int expiresAtMs;
  final String? accountId;
  final String? email;
  final String? planType;

  const OpenAiSession({
    required this.accessToken,
    required this.refreshToken,
    this.idToken,
    required this.expiresAtMs,
    this.accountId,
    this.email,
    this.planType,
  });

  bool get isStale =>
      expiresAtMs - DateTime.now().millisecondsSinceEpoch < 120000;

  String get displayName {
    if (email != null && email!.isNotEmpty) return email!;
    if (planType != null && planType!.isNotEmpty) return 'ChatGPT ($planType)';
    return 'ChatGPT signed in';
  }
}

class OpenAiDeviceAuth {
  final http.Client _http;
  OpenAiDeviceAuth({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Future<bool> isSignedIn() async => (await loadSession()) != null;

  Future<OpenAiSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_kAccess);
    final refresh = prefs.getString(_kRefresh);
    if (access == null || refresh == null) return null;
    return OpenAiSession(
      accessToken: access,
      refreshToken: refresh,
      idToken: prefs.getString(_kId),
      expiresAtMs: prefs.getInt(_kExpires) ?? 0,
      accountId: prefs.getString(_kAccount),
      email: prefs.getString(_kEmail),
      planType: prefs.getString(_kPlan),
    );
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kId);
    await prefs.remove(_kExpires);
    await prefs.remove(_kAccount);
    await prefs.remove(_kEmail);
    await prefs.remove(_kPlan);
  }

  Future<DeviceLoginPending> startDeviceLogin() async {
    final response = await _http.post(
      Uri.parse('$kOpenAiIssuer/api/accounts/deviceauth/usercode'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'client_id': kOpenAiClientId}),
    );
    if (response.statusCode == 404) {
      throw Exception('Device-code login is not enabled on this OpenAI account.');
    }
    if (response.statusCode != 200) {
      throw Exception('Could not start ChatGPT login (${response.statusCode})');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final userCode = (json['user_code'] ?? json['usercode'])?.toString();
    final authId = json['device_auth_id']?.toString();
    if (userCode == null || userCode.isEmpty || authId == null || authId.isEmpty) {
      throw Exception('OpenAI did not return a device code');
    }
    final intervalRaw = json['interval'];
    final intervalSec = intervalRaw is num
        ? intervalRaw.toInt()
        : int.tryParse(intervalRaw?.toString() ?? '') ?? 5;
    return DeviceLoginPending(
      userCode: userCode,
      deviceAuthId: authId,
      interval: Duration(seconds: intervalSec < 1 ? 5 : intervalSec),
    );
  }

  /// Poll until the user enters [pending.userCode] at the verification URL.
  Future<OpenAiSession> waitForApproval(
    DeviceLoginPending pending, {
    Duration timeout = const Duration(minutes: 15),
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var interval = pending.interval;
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() == true) {
        throw Exception('Sign-in cancelled');
      }
      await Future<void>.delayed(interval);
      if (isCancelled?.call() == true) {
        throw Exception('Sign-in cancelled');
      }
      final poll = await _http.post(
        Uri.parse('$kOpenAiIssuer/api/accounts/deviceauth/token'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'device_auth_id': pending.deviceAuthId,
          'user_code': pending.userCode,
        }),
      );
      if (poll.statusCode == 200) {
        final json = jsonDecode(poll.body) as Map<String, dynamic>;
        final code = json['authorization_code']?.toString();
        final verifier = json['code_verifier']?.toString();
        if (code == null || verifier == null) {
          throw Exception('OpenAI approval was missing an authorization code');
        }
        final session = await _exchangeCode(code, verifier);
        await _persist(session);
        return session;
      }
      if (poll.statusCode == 403 || poll.statusCode == 404) {
        continue;
      }
      throw Exception('ChatGPT approval failed (${poll.statusCode})');
    }
    throw Exception('ChatGPT sign-in timed out. Start again.');
  }

  Future<OpenAiSession> ensureFreshSession() async {
    final current = await loadSession();
    if (current == null) {
      throw Exception('Not signed in to ChatGPT. Open the AI tab and sign in.');
    }
    if (!current.isStale) return current;
    return refresh(current);
  }

  Future<OpenAiSession> refresh(OpenAiSession current) async {
    final response = await _http.post(
      Uri.parse('$kOpenAiIssuer/oauth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': kOpenAiClientId,
        'refresh_token': current.refreshToken,
        'scope': 'openid profile email offline_access',
      },
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      await signOut();
      throw Exception('ChatGPT session expired. Sign in again.');
    }
    if (response.statusCode != 200) {
      throw Exception('Could not refresh ChatGPT session (${response.statusCode})');
    }
    final session = sessionFromTokenResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
      fallbackRefresh: current.refreshToken,
    );
    await _persist(session);
    return session;
  }

  Future<OpenAiSession> _exchangeCode(String code, String verifier) async {
    final response = await _http.post(
      Uri.parse('$kOpenAiIssuer/oauth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': kOpenAiClientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': kOpenAiRedirectUri,
      },
    );
    if (response.statusCode != 200) {
      throw Exception('ChatGPT token exchange failed (${response.statusCode})');
    }
    return sessionFromTokenResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> _persist(OpenAiSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, session.accessToken);
    await prefs.setString(_kRefresh, session.refreshToken);
    if (session.idToken != null) await prefs.setString(_kId, session.idToken!);
    await prefs.setInt(_kExpires, session.expiresAtMs);
    if (session.accountId != null) await prefs.setString(_kAccount, session.accountId!);
    if (session.email != null) await prefs.setString(_kEmail, session.email!);
    if (session.planType != null) await prefs.setString(_kPlan, session.planType!);
  }

  static OpenAiSession sessionFromTokenResponse(
    Map<String, dynamic> json, {
    String? fallbackRefresh,
  }) {
    final access = json['access_token']?.toString();
    final refresh = json['refresh_token']?.toString() ?? fallbackRefresh;
    if (access == null || refresh == null) {
      throw Exception('OpenAI token response was incomplete');
    }
    final expiresIn = json['expires_in'] is num
        ? (json['expires_in'] as num).toInt()
        : int.tryParse('${json['expires_in']}') ?? 3600;
    final idToken = json['id_token']?.toString();
    final claims = jwtClaims(idToken) ?? jwtClaims(access) ?? const {};
    final identity = chatgptIdentity(claims);
    return OpenAiSession(
      accessToken: access,
      refreshToken: refresh,
      idToken: idToken,
      expiresAtMs: DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
      accountId: identity.accountId,
      email: identity.email,
      planType: identity.planType,
    );
  }

  static ({String? accountId, String? email, String? planType}) chatgptIdentity(
    Map<String, dynamic> claims,
  ) {
    Map<String, dynamic>? asMap(Object? value) =>
        value is Map<String, dynamic> ? value : null;
    final auth = asMap(claims['https://api.openai.com/auth']);
    final profile = asMap(claims['https://api.openai.com/profile']);
    final accountId = auth?['chatgpt_account_id']?.toString() ??
        auth?['account_id']?.toString() ??
        claims['chatgpt_account_id']?.toString();
    final email = claims['email']?.toString() ?? profile?['email']?.toString();
    final planType = auth?['chatgpt_plan_type']?.toString() ??
        claims['chatgpt_plan_type']?.toString();
    return (accountId: accountId, email: email, planType: planType);
  }

  static Map<String, dynamic>? jwtClaims(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      var segment = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      final pad = segment.length % 4;
      if (pad != 0) segment += '=' * (4 - pad);
      final json = utf8.decode(base64.decode(segment));
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
