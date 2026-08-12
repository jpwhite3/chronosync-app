import 'package:chronosync/data/models/haptic_intensity.dart';
import 'package:chronosync/data/services/haptic_service.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingVibrationDriver implements VibrationDriver {
  bool hasVibrator = true;
  bool hasCustomSupport = false;
  int vibrateCalls = 0;
  List<int>? pattern;
  List<int>? intensities;

  @override
  Future<void> cancel() async {}

  @override
  Future<bool> hasCustomVibrationsSupport() async => hasCustomSupport;

  @override
  Future<bool> hasVibratorAvailable() async => hasVibrator;

  @override
  Future<void> vibrate({
    int? duration,
    int? amplitude,
    List<int>? pattern,
    List<int>? intensities,
  }) async {
    vibrateCalls += 1;
    this.pattern = pattern;
    this.intensities = intensities;
  }
}

void main() {
  test('fallback vibration supplies one intensity per pattern entry', () async {
    final _RecordingVibrationDriver driver = _RecordingVibrationDriver();
    final HapticService service = HapticService(
      vibrationDriver: driver,
      isWeb: false,
      isAndroid: false,
    );

    await service.triggerHaptic(HapticIntensity.strong);

    expect(driver.pattern, <int>[0, 100, 50, 100]);
    expect(driver.intensities, <int>[0, 255, 0, 255]);
  });

  test('none never asks the platform to vibrate', () async {
    final _RecordingVibrationDriver driver = _RecordingVibrationDriver();
    final HapticService service = HapticService(
      vibrationDriver: driver,
      isWeb: false,
      isAndroid: false,
    );

    await service.triggerHaptic(HapticIntensity.none);

    expect(driver.vibrateCalls, 0);
  });
}
