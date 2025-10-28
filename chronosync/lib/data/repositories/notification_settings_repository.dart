import 'package:hive_flutter/hive_flutter.dart';
import '../models/global_notification_settings.dart';

/// Repository for managing global notification settings
class NotificationSettingsRepository {
  static const String _boxName = 'notification_settings';
  static const String _globalSettingsKey = 'global_settings';

  Box<GlobalNotificationSettings>? _box;

  /// Initialize the repository (must be called before use)
  Future<void> init() async {
    if (_box != null) return; // Already initialized
    _box = await Hive.openBox<GlobalNotificationSettings>(_boxName);
  }

  /// Get current global notification settings
  Future<GlobalNotificationSettings> getGlobalSettings() async {
    await init();
    return _box!.get(
      _globalSettingsKey,
      defaultValue: GlobalNotificationSettings.defaults(),
    )!;
  }

  /// Save global notification settings
  Future<void> saveGlobalSettings(GlobalNotificationSettings settings) async {
    await init();
    await _box!.put(_globalSettingsKey, settings);
  }

  /// Watch for changes to global settings
  Stream<GlobalNotificationSettings> watchGlobalSettings() async* {
    await init();
    
    // Emit current value first
    yield await getGlobalSettings();
    
    // Then emit updates
    await for (final _ in _box!.watch(key: _globalSettingsKey)) {
      yield await getGlobalSettings();
    }
  }

  /// Close the repository
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }
}
