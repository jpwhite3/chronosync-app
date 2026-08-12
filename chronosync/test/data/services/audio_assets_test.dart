import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final String asset in <String>[
    'assets/audio/auto_progress_beep.mp3',
    'assets/audio/preview_beep.mp3',
  ]) {
    test('$asset contains playable audio data', () async {
      final ByteData bytes = await rootBundle.load(asset);
      expect(bytes.lengthInBytes, greaterThan(1000));
    });
  }
}
