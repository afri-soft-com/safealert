import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/theme.dart';
import 'package:safealert/widgets/nav_bar.dart';
import 'package:safealert/widgets/top_bar.dart';

void main() {
  testWidgets('NavBar fits on narrow 320dp screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavBar(active: 'home', onTap: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Accueil'), findsOneWidget);
  });

  testWidgets('TopBar with long subtitle does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TopBar(sub: 'Bonjour, Citoyen avec un très long sous-titre 👋'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('TopBar renders on large tablet width', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.rouge),
        ),
        home: const Scaffold(
          body: TopBar(title: 'Tableau de bord — Votre quartier'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
