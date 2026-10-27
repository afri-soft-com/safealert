import 'package:flutter_test/flutter_test.dart';
import 'package:safealert/services/share_helper.dart';

void main() {
  group('ShareHelper.groupInviteUrl', () {
    test('never embeds /api in the invite URL', () {
      final url = ShareHelper.groupInviteUrl('ABCD1234');
      expect(url, isNot(contains('/api/')));
      expect(url, contains('/g/ABCD1234'));
      expect(url.startsWith('https://'), isTrue);
    });

    test('refuses empty codes that would 404 as JSON', () {
      final url = ShareHelper.groupInviteUrl('');
      expect(url, isNot(contains('/g/')));
    });

    test('publicWebOrigin is host only', () {
      expect(ShareHelper.publicWebOrigin, isNot(contains('/api')));
      expect(ShareHelper.publicWebOrigin.endsWith('/'), isFalse);
    });
  });
}
