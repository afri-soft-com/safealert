import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/auth_provider.dart';
import 'package:safealert/screens/login_screen.dart';
import 'package:safealert/services/local_pin_service.dart';
import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApiService fakeApi;
  late MemoryPinStore pinStore;
  late AuthProvider auth;
  var successCount = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeApi = FakeApiService();
    pinStore = MemoryPinStore();
    auth = AuthProvider(
      apiService: fakeApi,
      pinService: LocalPinService(store: pinStore),
    );
    successCount = 0;
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(
          home: LoginScreen(onSuccess: () => successCount++),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('returning user with PIN sees unlock, not SMS send', (tester) async {
    await LocalPinService(store: pinStore).setPin('123456', phone: '+243811234567');

    await pumpLogin(tester);

    expect(find.text('Code PIN oublié'), findsOneWidget);
    expect(find.text('Déverrouiller'), findsOneWidget);
    expect(find.text('Envoyer le code'), findsNothing);
  });

  testWidgets('forgot PIN requests OTP then allows a new PIN', (tester) async {
    await LocalPinService(store: pinStore).setPin('123456', phone: '+243811234567');
    fakeApi.onPost('/auth/request-code', () => {'message': 'ok', 'devCode': '654321'});
    fakeApi.onPost('/auth/verify-code', () => {
      'token': 'jwt-token',
      'user': {'id': 'u1', 'phone': '+243811234567', 'role': 'citizen'},
    });

    await pumpLogin(tester);
    await tester.tap(find.text('Code PIN oublié'));
    await tester.pumpAndSettle();

    expect(fakeApi.lastPath, '/auth/request-code');
    expect(fakeApi.lastBody, {'phone': '+243811234567'});
    expect(find.text('Vérifier'), findsOneWidget);

    await tester.tap(find.text('Vérifier'));
    await tester.pumpAndSettle();

    expect(find.text('Enregistrer le PIN'), findsOneWidget);
    expect(find.text('Envoyer le code'), findsNothing);

    final pinFields = find.byType(TextField);
    await tester.enterText(pinFields.at(0), '246810');
    await tester.enterText(pinFields.at(1), '246810');
    await tester.tap(find.text('Enregistrer le PIN'));
    await tester.pumpAndSettle();

    expect(successCount, 1);
    expect(auth.canEnterApp, true);
    expect(await LocalPinService(store: pinStore).verify('246810'), true);
  });

  testWidgets('restored session without PIN shows create PIN immediately', (tester) async {
    await fakeApi.setToken('valid-token');
    fakeApi.onGet('/auth/profile', () => {
      'id': 'u1',
      'phone': '+243812345678',
      'role': 'citizen',
    });
    await auth.checkAuth();

    await pumpLogin(tester);

    expect(find.text('Enregistrer le PIN'), findsOneWidget);
    expect(find.text('Envoyer le code'), findsNothing);
    expect(successCount, 0);
  });

  testWidgets('session needing PIN setup after checkAuth switches to create PIN', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Envoyer le code'), findsOneWidget);

    await fakeApi.setToken('valid-token');
    fakeApi.onGet('/auth/profile', () => {
      'id': 'u1',
      'phone': '+243812345678',
      'role': 'citizen',
    });
    await auth.checkAuth();
    await tester.pumpAndSettle();

    expect(find.text('Enregistrer le PIN'), findsOneWidget);
    expect(find.text('Envoyer le code'), findsNothing);
    expect(successCount, 0);
  });

  testWidgets('first OTP login forces PIN creation before success', (tester) async {
    fakeApi.onPost('/auth/request-code', () => {'message': 'ok', 'devCode': '111222'});
    fakeApi.onPost('/auth/verify-code', () => {
      'token': 'jwt-token',
      'user': {'id': 'u1', 'phone': '+243812345678', 'role': 'citizen'},
    });

    await pumpLogin(tester);

    expect(find.text('Envoyer le code'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '+243812345678');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();

    expect(find.text('Vérifier'), findsOneWidget);
    await tester.tap(find.text('Vérifier'));
    await tester.pumpAndSettle();

    expect(successCount, 0);
    expect(find.text('Enregistrer le PIN'), findsOneWidget);

    final pinFields = find.byType(TextField);
    await tester.enterText(pinFields.at(0), '112233');
    await tester.enterText(pinFields.at(1), '112233');
    await tester.tap(find.text('Enregistrer le PIN'));
    await tester.pumpAndSettle();

    expect(successCount, 1);
    expect(auth.canEnterApp, true);
  });

  testWidgets('after logout the PIN screen is shown and unlocks without SMS', (tester) async {
    fakeApi.onPost('/auth/request-code', () => {'message': 'ok', 'devCode': '111222'});
    fakeApi.onPost('/auth/verify-code', () => {
      'token': 'jwt-token',
      'user': {'id': 'u1', 'phone': '+243812345678', 'role': 'citizen'},
    });

    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).first, '+243812345678');
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vérifier'));
    await tester.pumpAndSettle();
    final pinFields = find.byType(TextField);
    await tester.enterText(pinFields.at(0), '112233');
    await tester.enterText(pinFields.at(1), '112233');
    await tester.tap(find.text('Enregistrer le PIN'));
    await tester.pumpAndSettle();
    expect(auth.canEnterApp, true);

    await auth.logout();
    successCount = 0;
    await pumpLogin(tester);

    expect(find.text('Déverrouiller'), findsOneWidget);
    expect(find.text('Code PIN oublié'), findsOneWidget);
    expect(find.text('Changer de numéro'), findsOneWidget);
    expect(find.text('Envoyer le code'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '112233');
    await tester.tap(find.text('Déverrouiller'));
    await tester.pumpAndSettle();

    expect(successCount, 1);
    expect(auth.canEnterApp, true);
    expect(fakeApi.lastPath, isNot('/auth/request-code'));
  });

  testWidgets('changer de numéro after PIN returns to the phone field', (tester) async {
    await LocalPinService(store: pinStore).setPin('123456', phone: '+243811234567');

    await pumpLogin(tester);
    expect(find.text('Déverrouiller'), findsOneWidget);

    await tester.tap(find.text('Changer de numéro'));
    await tester.pumpAndSettle();

    expect(find.text('Envoyer le code'), findsOneWidget);
    expect(find.text('Déverrouiller'), findsNothing);
    expect(auth.hasLocalPin, false);
  });
}
