import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/providers/admin_provider.dart';

void main() {
  test('AdminProvider roleLabels includes platform_admin', () {
    expect(AdminProvider.roleLabels['platform_admin'], 'Administrateur');
    expect(AdminProvider.roleLabels['leader'], 'Responsable');
    expect(AdminProvider.roleLabels.length, 4);
  });
}
