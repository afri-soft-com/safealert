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
        home: AppUpdateBanner(
          latestVersion: '1.0.8',
          onUpdate: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(find.text('Nouvelle version disponible'), findsOneWidget);
    expect(find.textContaining('SafeAlert 1.0.8'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
  });
}
