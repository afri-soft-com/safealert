import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/main.dart';

void main() {
  testWidgets('App launches with splash screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SafeAlertApp());
    await tester.pumpAndSettle();
    expect(find.text('SafeAlert'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
  });
}
