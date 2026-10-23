import 'package:flutter/foundation.dart';
import 'package:smart_auth/smart_auth.dart';

typedef OtpCodeCallback = void Function(String code);

/// Android SMS User Consent — system dialog then OTP fill (no hash in SMS).
/// iOS: Messages suggestion via [AutofillHints.oneTimeCode] only (no-op here).
Future<void> startOtpSmsListen({OtpCodeCallback? onCode}) async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final res = await SmartAuth.instance.getSmsWithUserConsentApi(
      matcher: r'(\d{6})',
    );
    if (!res.hasData) return;
    final raw = res.requireData.code;
    if (raw == null || raw.isEmpty) return;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return;
    final six = digits.length == 6 ? digits : digits.substring(digits.length - 6);
    onCode?.call(six);
  } catch (_) {}
}

void stopOtpSmsListen() {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    SmartAuth.instance.removeUserConsentApiListener();
  } catch (_) {}
}
