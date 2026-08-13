import 'package:chronosync/data/models/device_sound.dart';
import 'package:chronosync/data/repositories/device_audio_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop bundled sound uses auto-advance product language', () async {
    final List<DeviceSound> sounds = await DeviceAudioRepository()
        .getAvailableSounds();

    expect(
      sounds.map<String>((DeviceSound sound) => sound.displayName),
      contains('Auto-advance beep'),
    );
  });
}
