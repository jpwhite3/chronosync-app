import 'dart:io';

import 'package:chronosync/core/platform/initial_invitation_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialInvitationUri', () {
    test('consumes a stashed invitation for the current page', () {
      final _MemoryStore store = _MemoryStore(
        'https://app.example.com/join?source=qr#invite=secret-payload',
      );

      final Uri result = initialInvitationUri(
        Uri.parse('https://app.example.com/join?source=qr'),
        store: store,
      );

      expect(result.fragment, 'invite=secret-payload');
      expect(store.value, isNull);
    });

    test('discards stale or malformed stashed values', () {
      for (final String value in <String>[
        'not a URI',
        'https://other.example.com/join#invite=secret-payload',
        'https://app.example.com/other#invite=secret-payload',
        'https://app.example.com/join#unrelated=value',
      ]) {
        final _MemoryStore store = _MemoryStore(value);
        final Uri current = Uri.parse('https://app.example.com/join');

        expect(initialInvitationUri(current, store: store), current);
        expect(store.value, isNull);
      }
    });

    test('falls back safely when browser storage is unavailable', () {
      final Uri current = Uri.parse(
        'https://app.example.com/#invite=fallback-payload',
      );

      expect(initialInvitationUri(current, store: _ThrowingStore()), current);
    });
  });

  test('web bootstrap hides invitation secrets before Flutter starts', () {
    final String index = File('web/index.html').readAsStringSync();
    final String bootstrap = File(
      'web/invitation_bootstrap.js',
    ).readAsStringSync();

    final int invitationScript = index.indexOf('invitation_bootstrap.js');
    final int flutterScript = index.indexOf('flutter_bootstrap.js');
    expect(invitationScript, greaterThanOrEqualTo(0));
    expect(flutterScript, greaterThan(invitationScript));
    expect(bootstrap, contains('__chronosyncTakeInitialInvitationUrl'));
    expect(bootstrap, contains('history.replaceState'));
    expect(bootstrap, contains("params.has('invite')"));
    expect(bootstrap, isNot(contains('sessionStorage')));
    expect(bootstrap, isNot(contains('localStorage')));
    expect(bootstrap, contains('delete window[bridgeName]'));
  });
}

final class _MemoryStore implements PendingInvitationUrlStore {
  _MemoryStore(this.value);

  String? value;

  @override
  String? read() => value;

  @override
  void remove() => value = null;
}

final class _ThrowingStore implements PendingInvitationUrlStore {
  @override
  String? read() => throw StateError('storage unavailable');

  @override
  void remove() => throw StateError('storage unavailable');
}
