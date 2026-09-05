import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/ai/openai_device_auth.dart';

void main() {
  test('jwtClaims reads ChatGPT account metadata', () {
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'email': 'you@example.com',
              'https://api.openai.com/auth': {
                'chatgpt_account_id': 'acct_1',
                'chatgpt_plan_type': 'plus',
              },
            }),
          ),
        )
        .replaceAll('=', '');
    final token = 'aaa.$payload.sig';
    final claims = OpenAiDeviceAuth.jwtClaims(token);
    expect(claims!['email'], 'you@example.com');
    final session = OpenAiDeviceAuth.sessionFromTokenResponse({
      'access_token': token,
      'refresh_token': 'rt',
      'id_token': token,
      'expires_in': 3600,
    });
    expect(session.accountId, 'acct_1');
    expect(session.email, 'you@example.com');
    expect(session.planType, 'plus');
    expect(session.displayName, 'you@example.com');
  });
}
