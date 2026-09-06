import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/polar/polar_errors.dart';

void main() {
  test('treats Polar ERROR_ALREADY_IN_STATE as benign', () {
    const raw =
        'PPG stream error: PlatformException(com.polar.androidcommunications.api.ble.exceptions.BleControlPointCommandError: pmd cp command REQUEST_MEASUREMENT_START error: ERROR_ALREADY_IN_STATE, pmd cp command REQUEST_MEASUREMENT_START error: ERROR_ALREADY_IN_STATE, null, null)';
    expect(isAlreadyInStateError(raw), isTrue);
    expect(friendlyPolarError(raw, stream: 'PPG'), 'PPG is already measuring.');
    expect(friendlyPolarError(raw, stream: 'PPG').contains('PlatformException'), isFalse);
  });

  test('other failures stay short and do not dump the exception', () {
    const raw = 'PlatformException(timeout, BLE timeout, null, null)';
    expect(isAlreadyInStateError(raw), isFalse);
    expect(friendlyPolarError(raw, stream: 'PPG'), contains('timed out'));
    expect(friendlyPolarError(raw, stream: 'PPG').contains('PlatformException'), isFalse);
  });
}
