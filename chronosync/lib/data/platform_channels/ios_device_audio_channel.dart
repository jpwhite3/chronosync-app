import 'package:flutter/services.dart';
import '../models/device_sound.dart';

/// Platform channel for iOS device sounds
class IosDeviceAudioChannel {
  static const MethodChannel _channel =
      MethodChannel('com.chronosync/device_audio_ios');

  /// Get list of available system notification sounds on iOS
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
      return [DeviceSound.systemDefault()];
    }
  }

  /// Preview a sound by its file path
  Future<void> previewSound(String filePath) async {
    try {
      await _channel.invokeMethod('previewSound', {'filePath': filePath});
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
