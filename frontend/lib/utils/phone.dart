/// Normalise un numéro vers E.164 (RDC +243) pour correspondre au backend.
String? normalizePhone(String raw) {
  var phone = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  if (phone.isEmpty) return null;

  if (phone.startsWith('00')) {
    phone = '+${phone.substring(2)}';
  } else if (phone.startsWith('0') && !phone.startsWith('+')) {
    phone = '+243${phone.substring(1)}';
  } else if (RegExp(r'^243\d{9}$').hasMatch(phone)) {
    phone = '+$phone';
  } else if (RegExp(r'^\d{9}$').hasMatch(phone)) {
    phone = '+243$phone';
  }

  if (!RegExp(r'^\+\d{10,15}$').hasMatch(phone)) return null;
  return phone;
}
