import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/utils/phone.dart';

void main() {
  test('normalizePhone converts local DRC formats to E.164', () {
    expect(normalizePhone('+243971163574'), '+243971163574');
    expect(normalizePhone('971163574'), '+243971163574');
    expect(normalizePhone('0971163574'), '+243971163574');
    expect(normalizePhone('+243 97 116 3574'), '+243971163574');
  });

  test('normalizePhone rejects invalid input', () {
    expect(normalizePhone(''), isNull);
    expect(normalizePhone('abc'), isNull);
  });
}
