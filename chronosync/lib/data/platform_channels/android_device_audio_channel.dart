import 'package:flutter/services.dart';
import '../models/device_sound.dart';

/// Platform channel for Android device sounds
class AndroidDeviceAudioChannel {
  static const MethodChannel _channel =
      MethodChannel('com.chronosync/device_audio_android');

  /// Get list of available notification sounds on Android
  Future<List<DeviceSound>> getAvailableSounds() async {
    try {
      final List<dynamic> sounds =
          await _channel.invokeMethod('getAvailableSounds');
      
      return sounds.map((soundData) {
        return DeviceSound(
          id: soundData['id'] as String,
          displayName: soundData['displayName'] as String,
          filePath: soundData['filePath'] as String,
          isSystemSound: soundData['isSystemSound'] as bool? ?? true,
        );
      }).toList();
    } on PlatformException {
      // If platform method fails, return system default only
      return <DeviceSound>[DeviceSound.systemDefault()];
    }
  }

  /// Preview a sound by its URI
  Future<void> previewSound(String soundUri) async {
    try {
      await _channel.invokeMethod('previewSound', <String, String>{'soundUri': soundUri});
    } on PlatformException catch (e) {
      // Silently fail preview
      print('Failed to preview sound: ${e.message}');
    }
  }

  /// Stop any currently playing preview
  Future<void> stopPreview() async {
    try {
      await _channel.invokeMethod('stopPreview');
    } on PlatformException catch (e) {
      print('Failed to stop preview: ${e.message}');
    }
  }
}
