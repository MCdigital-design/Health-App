/// Polar BLE / platform-channel error helpers.
///
/// The native SDK reports `ERROR_ALREADY_IN_STATE` when the app issues
/// `REQUEST_MEASUREMENT_START` while that measurement is already running.
/// That is not a user-facing failure — it usually means the watchdog
/// restarted a stream whose Polar timestamps looked "stale" next to the
/// phone clock, or Live called start again after connect already started it.
library;

bool isAlreadyInStateError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('already_in_state') ||
      text.contains('error_already_in_state') ||
      text.contains('already in state');
}

/// One-line message for SnackBars. Never forwards a raw PlatformException.
String friendlyPolarError(Object error, {required String stream}) {
  if (isAlreadyInStateError(error)) {
    return '$stream is already measuring.';
  }
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('bledisconnected') || lower.contains('disconnected')) {
    return 'Sensor disconnected.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return '$stream timed out. Try Stop, then Start.';
  }
  return '$stream failed. Try Stop, then Start.';
}
