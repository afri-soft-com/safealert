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
}
