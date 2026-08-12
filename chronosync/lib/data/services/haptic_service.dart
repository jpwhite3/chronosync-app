import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import '../models/haptic_intensity.dart';

abstract interface class VibrationDriver {
  Future<bool> hasVibratorAvailable();

  Future<bool> hasCustomVibrationsSupport();

  Future<void> vibrate({
    int? duration,
    int? amplitude,
    List<int>? pattern,
    List<int>? intensities,
  });

  Future<void> cancel();
}

final class PlatformVibrationDriver implements VibrationDriver {
  const PlatformVibrationDriver();

  @override
  Future<bool> hasVibratorAvailable() => Vibration.hasVibrator();

  @override
  Future<bool> hasCustomVibrationsSupport() {
    return Vibration.hasCustomVibrationsSupport();
  }

  @override
  Future<void> vibrate({
    int? duration,
    int? amplitude,
    List<int>? pattern,
    List<int>? intensities,
  }) {
    return Vibration.vibrate(
      duration: duration ?? 500,
      amplitude: amplitude ?? -1,
      pattern: pattern ?? const <int>[],
      intensities: intensities ?? const <int>[],
    );
  }

  @override
  Future<void> cancel() => Vibration.cancel();
}

/// Service for triggering haptic feedback
class HapticService {
  HapticService({
    VibrationDriver? vibrationDriver,
    bool? isWeb,
    bool? isAndroid,
  }) : _vibrationDriver = vibrationDriver ?? const PlatformVibrationDriver(),
       _isWeb = isWeb ?? kIsWeb,
       _isAndroid = isAndroid ?? Platform.isAndroid;

  final VibrationDriver _vibrationDriver;
  final bool _isWeb;
  final bool _isAndroid;

  /// Trigger haptic feedback with specified intensity
  Future<void> triggerHaptic(HapticIntensity intensity) async {
    if (_isWeb) return; // Web doesn't support vibration

    // Don't vibrate if intensity is none
    if (intensity == HapticIntensity.none) return;

    try {
      // Check if device has vibrator
      final bool hasVibrator = await _vibrationDriver.hasVibratorAvailable();
      if (!hasVibrator) return;

      // Check if custom vibration is supported (Android)
      final bool hasCustom = await _vibrationDriver
          .hasCustomVibrationsSupport();

      if (hasCustom && _isAndroid) {
        // Android: Use amplitude-based vibration
        await _vibrationDriver.vibrate(
          duration: 200,
          amplitude: intensity.amplitude,
        );
      } else {
        // iOS or fallback: Use simple vibration with pattern
        // iOS doesn't support custom amplitude, so we use duration patterns
        final List<int> pattern = _getVibrationPattern(intensity);
        await _vibrationDriver.vibrate(
          pattern: pattern,
          intensities: _getIntensities(intensity, pattern.length),
        );
      }
    } on Object {
      // Silently fail if haptic feedback is not available
      debugPrint('Haptic feedback could not be delivered.');
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
  List<int> _getIntensities(HapticIntensity intensity, int patternLength) {
    final int amplitude = intensity.amplitude;
    return List<int>.generate(
      patternLength,
      (int index) => index.isEven ? 0 : amplitude,
      growable: false,
    );
  }

  /// Stop any ongoing vibration
  Future<void> stopHaptic() async {
    if (_isWeb) return;

    try {
      await _vibrationDriver.cancel();
    } on Object {
      debugPrint('Haptic feedback could not be stopped.');
    }
  }
}
