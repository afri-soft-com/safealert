import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/services/fcm_service.dart';

void main() {
  group('FCMService.isOwnPushData', () {
    test('skips sound when push is from the current user', () {
      expect(
        FCMService.isOwnPushData(
          {'type': 'sos_alert', 'userId': 'me'},
          currentUserId: 'me',
        ),
        isTrue,
      );
    });

    test('plays sound when push is from another user', () {
      expect(
        FCMService.isOwnPushData(
          {'type': 'nearby_alert', 'userId': 'other'},
          currentUserId: 'me',
        ),
        isFalse,
      );
    });

    test('does not treat missing sender as own push', () {
      expect(
        FCMService.isOwnPushData({'type': 'sos_alert'}, currentUserId: 'me'),
        isFalse,
      );
    });
  });
}
