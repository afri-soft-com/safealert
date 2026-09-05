import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/auth_provider.dart';
import 'package:safealert/screens/login_screen.dart';
import 'package:safealert/services/local_pin_service.dart';
import 'mocks.dart';

AuthProvider _auth({FakeApiService? api, MemoryPinStore? store}) {
  return AuthProvider(
    apiService: api ?? FakeApiService(),
    pinService: LocalPinService(store: store ?? MemoryPinStore()),
  );
}

void main() {
  testWidgets('Login phone step fits on 320dp width', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetViewInsets();
    });

    final auth = _auth();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(
          home: LoginScreen(onSuccess: _noop),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Envoyer le code'), findsOneWidget);
  });

  testWidgets('Login OTP step with keyboard does not overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetViewInsets();
    });

    final fakeApi = FakeApiService();
    fakeApi.onPost('/auth/request-code', () => {'message': 'ok', 'devCode': '123456'});
    final auth = _auth(api: fakeApi);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(
          home: LoginScreen(onSuccess: _noop),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '+243812345678');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Vérifier'), findsOneWidget);
    expect(find.textContaining('Code de test'), findsOneWidget);

    await tester.tap(find.text('Nouveau compte'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Login PIN unlock with keyboard does not overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetViewInsets();
    });

    final store = MemoryPinStore();
    await LocalPinService(store: store).setPin('123456', phone: '+243811234567');
    final auth = _auth(store: store);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(
          home: LoginScreen(onSuccess: _noop),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Code PIN oublié'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
