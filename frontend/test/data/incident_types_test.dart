import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/data/incident_types.dart';

void main() {
  test('keeps SOS labels distinct from signalement types', () {
    expect(incidentTypeLabel('sos'), 'Alerte SOS');
    expect(incidentTypeLabel('sos_discret'), 'SOS Discret');
    expect(incidentTypeLabel('vol'), 'Vol');
  });

  test('prefers catalog label over fallback', () {
    const catalog = [IncidentTypeDef(slug: 'vol', labelFr: 'Vol à l\'arraché')];
    expect(incidentTypeLabel('vol', catalog: catalog), 'Vol à l\'arraché');
  });

  test('iOS report form hides crime report types (App Review 2.1)', () {
    final ios = reportableIncidentTypes(kFallbackIncidentTypes, platform: TargetPlatform.iOS)
        .map((t) => t.slug)
        .toList();
    expect(ios, ['accident', 'incendie', 'autre']);
  });

  test('Android keeps every report type', () {
    final android = reportableIncidentTypes(kFallbackIncidentTypes, platform: TargetPlatform.android);
    expect(android.length, kFallbackIncidentTypes.length);
  });
}
