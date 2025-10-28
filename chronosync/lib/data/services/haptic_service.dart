import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import '../models/haptic_intensity.dart';

/// Service for triggering haptic feedback
class HapticService {
  /// Trigger haptic feedback with specified intensity
  Future<void> triggerHaptic(HapticIntensity intensity) async {
    if (kIsWeb) return; // Web doesn't support vibration

    // Don't vibrate if intensity is none
    if (intensity == HapticIntensity.none) return;

    try {
      // Check if device has vibrator
      final bool hasVibrator = await Vibration.hasVibrator();
      if (!hasVibrator) return;

      // Check if custom vibration is supported (Android)
      final bool hasCustom = await Vibration.hasCustomVibrationsSupport();

      if (hasCustom && Platform.isAndroid) {
        // Android: Use amplitude-based vibration
        await Vibration.vibrate(
          duration: 200,
          amplitude: intensity.amplitude,
        );
      } else {
        // iOS or fallback: Use simple vibration with pattern
        // iOS doesn't support custom amplitude, so we use duration patterns
        final List<int> pattern = _getVibrationPattern(intensity);
        await Vibration.vibrate(
          pattern: pattern,
          intensities: _getIntensities(intensity, pattern.length ~/ 2),
        );
      }
    } catch (e) {
      // Silently fail if haptic feedback is not available
      debugPrint('Haptic feedback error: $e');
    }
  }

  /// Get vibration pattern for iOS (duration-based intensity simulation)
  List<int> _getVibrationPattern(HapticIntensity intensity) {
    switch (intensity) {
      case HapticIntensity.none:
        return <int>[0];
      case HapticIntensity.light:
        return <int>[0, 100]; // Single short buzz
      case HapticIntensity.medium:
        return <int>[0, 200]; // Single medium buzz
      case HapticIntensity.strong:
        return <int>[0, 100, 50, 100]; // Double buzz pattern
    }
  }

  /// Get intensities array for vibration pattern
  List<int> _getIntensities(HapticIntensity intensity, int patternCount) {
    final int amplitude = intensity.amplitude;
    return List.filled(patternCount, amplitude);
  }

  /// Stop any ongoing vibration
  Future<void> stopHaptic() async {
    if (kIsWeb) return;

    try {
      await Vibration.cancel();
    } catch (e) {
      debugPrint('Stop haptic error: $e');
    }
  }
}
