import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/services/app_update_service.dart';

void main() {
  test('polls mid-session every 5–15 minutes (not only at launch)', () {
    expect(AppUpdateService.pollInterval.inMinutes, inInclusiveRange(5, 15));
    expect(
      AppUpdateService.minCheckGap,
      lessThan(AppUpdateService.pollInterval),
    );
  });

  test('compareVersions treats a newer remote as an update', () {
    expect(AppUpdateService.compareVersions('1.0.7', '1.0.8'), lessThan(0));
    expect(AppUpdateService.compareVersions('1.0.8', '1.0.8'), 0);
    expect(AppUpdateService.compareVersions('1.0.9', '1.0.8'), greaterThan(0));
    expect(AppUpdateService.compareVersions('1.0.9', '1.0.9'), 0);
  });

  testWidgets('AppUpdateBanner shows French copy and version', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(
            latestVersion: '1.0.8',
            currentVersion: '1.0.7',
            onUpdate: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.text('Nouvelle version disponible'), findsOneWidget);
    expect(find.textContaining('1.0.7 → 1.0.8'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
  });

  testWidgets('AppUpdateBanner shows build when versions match', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(
            latestVersion: '1.0.51 (74)',
            currentVersion: '1.0.51 (73)',
            onUpdate: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('1.0.51 (73) → 1.0.51 (74)'), findsOneWidget);
  });

  testWidgets('AppUpdateBanner fits a narrow phone without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(
            latestVersion: '1.0.80 (108)',
            currentVersion: '1.0.79 (107)',
            includeTopSafeArea: true,
            onUpdate: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Mettre à jour'), findsOneWidget);
  });
}
