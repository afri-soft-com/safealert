import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safealert/providers/admin_provider.dart';
import 'package:safealert/providers/auth_provider.dart';
import 'package:safealert/providers/incident_provider.dart';
import 'package:safealert/screens/admin_screen.dart';
import 'package:safealert/screens/dashboard_screen.dart';
import 'package:safealert/screens/help_manual_screen.dart';
import 'package:safealert/screens/home_screen.dart';
import 'package:safealert/screens/privacy_screen.dart';
import 'package:safealert/screens/safety_screen.dart';
import 'package:safealert/screens/settings_screen.dart';
import 'package:safealert/screens/sos_screen.dart';
import 'package:safealert/screens/heatmap_screen.dart';
import 'package:safealert/theme.dart';
import 'mocks.dart';

void main() {
  final viewports = <Size>[
    const Size(320, 568),
    const Size(360, 640),
  ];

  for (final size in viewports) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('HomeScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, _wrapProviders(HomeScreen(onNavigate: (_) {})));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SOSScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, _wrapProviders(
        SOSScreen(onBack: () {}),
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('APPUYER'), findsOneWidget);
    });

    testWidgets('DashboardScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, _wrapProviders(
        DashboardScreen(onNavigate: (_) {}),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, _wrapProviders(
        SettingsScreen(onBack: () {}, onLogout: () {}),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SafetyScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, _wrapProviders(
        SafetyScreen(onNavigate: (_) {}),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('HeatmapScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, _wrapProviders(
        HeatmapScreen(onNavigate: (_) {}),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('PrivacyScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppColors.rouge)),
        home: PrivacyScreen(onBack: () {}),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('HelpManualScreen fits on $label', (tester) async {
      await _pumpNarrow(tester, size, MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppColors.rouge)),
        home: HelpManualScreen(onBack: () {}),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AdminScreen fits on $label', (tester) async {
      final fakeApi = FakeApiService();
      fakeApi.onGet('/admin/users?page=1&limit=20', () => {
        'data': [
          {
            'id': 'u1',
            'pseudo': 'Citoyen avec un très long pseudo qui déborde',
            'phone': '+243812345678901',
            'role': 'citizen',
            'sector_name': 'Gombe centre-ville historique',
          },
        ],
        'total': 1,
        'page': 1,
      });
      fakeApi.onGet('/admin/partners', () => {
        'data': [
          {
            'id': 'p1',
            'partner_name': 'ONG Partenaire Internationale avec nom très long',
            'api_key': 'sk_live_abcdefghijklmnop',
            'is_active': true,
          },
        ],
      });

      await _pumpNarrow(tester, size, MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => IncidentProvider(apiService: fakeApi)),
          ChangeNotifierProvider(create: (_) => AdminProvider(apiService: fakeApi)),
        ],
        child: MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppColors.rouge)),
          home: AdminScreen(onNavigate: (_) {}),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpNarrow(WidgetTester tester, Size size, Widget app) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Widget _wrapProviders(Widget child) {
  final fakeApi = FakeApiService();
  fakeApi.onGet('/map/incidents?limit=100&hours=24', () => {'data': []});
  fakeApi.onGet('/map/stats', () => {
    'total_incidents': 0,
    'total_sos': 0,
    'active_users': 0,
    'safe_zones': 0,
  });
  fakeApi.onGet('/map/heatmap?days=30', () => {'zones': []});

  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider(apiService: fakeApi)),
      ChangeNotifierProvider(
        create: (_) => IncidentProvider(apiService: fakeApi, localDatabase: FakeLocalDatabase()),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppColors.rouge)),
      home: child,
    ),
  );
}
