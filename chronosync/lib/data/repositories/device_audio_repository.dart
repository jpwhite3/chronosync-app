import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/device_sound.dart';
import '../platform_channels/ios_device_audio_channel.dart';
import '../platform_channels/android_device_audio_channel.dart';

/// Repository for managing device notification sounds
class DeviceAudioRepository {
  final IosDeviceAudioChannel _iosChannel = IosDeviceAudioChannel();
  final AndroidDeviceAudioChannel _androidChannel = AndroidDeviceAudioChannel();

  /// Get list of available device notification sounds
  Future<List<DeviceSound>> getAvailableSounds() async {
    if (kIsWeb) {
      // Web not supported yet
      return <DeviceSound>[DeviceSound.systemDefault()];
    }

    if (Platform.isIOS) {
      return await _iosChannel.getAvailableSounds();
    } else if (Platform.isAndroid) {
      return await _androidChannel.getAvailableSounds();
    }

    // Fallback for desktop platforms - return mock sounds for testing
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return <DeviceSound>[
        DeviceSound.systemDefault(),
        const DeviceSound(
          id: 'beep',
          displayName: 'Auto-Progress Beep',
          filePath: 'assets/audio/auto_progress_beep.mp3',
          isSystemSound: true,
        ),
      ];
    }

    // Fallback for unsupported platforms
    return <DeviceSound>[DeviceSound.systemDefault()];
  }

  /// Preview a notification sound
  Future<void> previewSound(String soundPath) async {
    if (kIsWeb) return;

    if (Platform.isIOS) {
      await _iosChannel.previewSound(soundPath);
    } else if (Platform.isAndroid) {
      await _androidChannel.previewSound(soundPath);
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      // Desktop: Audio preview has session conflicts with LiveTimerBloc
      // In production (iOS/Android), native platform channels handle this properly
      debugPrint('Audio preview not available on desktop (development platform)');
      debugPrint('Selected sound: $soundPath');
      // Skip playback on desktop to avoid audio session conflicts
    }
  }

  /// Stop any currently playing sound preview
  Future<void> stopPreview() async {
    if (kIsWeb) return;

    if (Platform.isIOS) {
      await _iosChannel.stopPreview();
    } else if (Platform.isAndroid) {
      await _androidChannel.stopPreview();
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      // Desktop: No preview player to stop
      debugPrint('No preview to stop on desktop');
    }
  }
}
