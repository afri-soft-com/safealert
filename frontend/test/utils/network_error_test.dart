import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/utils/network_error.dart';

void main() {
  group('mapKnownApiMessage', () {
    test('does not remap payment errors to trajet', () {
      expect(
        mapKnownApiMessage('Impossible de démarrer le paiement Mobile Money.'),
        contains('paiement Mobile Money'),
      );
      expect(
        mapKnownApiMessage('Impossible de démarrer le paiement Mobile Money.'),
        isNot(contains('trajet')),
      );
    });

    test('maps trajet start failures specifically', () {
      expect(
        mapKnownApiMessage('Impossible de démarrer le trajet. Réessayez.'),
        'Impossible de démarrer le trajet. Réessayez.',
      );
    });

    test('maps pay hub not configured', () {
      expect(
        mapKnownApiMessage('Paiement Mobile Money non configuré.'),
        contains('indisponible'),
      );
    });
  });

  group('userFacingError', () {
    test('ApiException payment message stays about payment', () {
      final msg = userFacingError(
        ApiException('Impossible de démarrer le paiement Mobile Money.', 400),
        fallback: 'Paiement Mobile Money indisponible',
      );
      expect(msg.toLowerCase(), contains('paiement'));
      expect(msg.toLowerCase(), isNot(contains('trajet')));
    });
  });
}
