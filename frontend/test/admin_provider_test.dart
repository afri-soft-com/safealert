import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/providers/admin_provider.dart';

void main() {
  test('AdminProvider roleLabels includes staff roles', () {
    expect(AdminProvider.roleLabels['platform_admin'], 'Super administrateur');
    expect(AdminProvider.roleLabels['admin'], 'Administrateur');
    expect(AdminProvider.roleLabels['leader'], 'Responsable');
    expect(AdminProvider.roleLabels.length, 5);
  });
}
