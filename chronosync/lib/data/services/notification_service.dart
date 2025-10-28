import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/event.dart';
import '../repositories/notification_settings_repository.dart';
import 'haptic_service.dart';

/// Service for managing event completion notifications and haptic feedback
class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final HapticService _hapticService = HapticService();
  final NotificationSettingsRepository _settingsRepository;

  bool _initialized = false;

  NotificationService({
    required NotificationSettingsRepository settingsRepository,
  }) : _settingsRepository = settingsRepository;

  /// Initialize the notification service
  Future<void> init() async {
    if (_initialized || kIsWeb) return;

    // Skip initialization for desktop platforms (not fully supported)
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      _initialized = true; // Mark as initialized but don't actually initialize
      return;
    }

    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(settings);
      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize notifications: $e');
    }
  }

  /// Handle event completion with notifications and haptics
  Future<void> onEventComplete(Event event) async {
    try {
      // Get effective settings (event override or global)
      final globalSettings = await _settingsRepository.getGlobalSettings();
      final eventSettings = event.notificationSettings;

      // Determine effective values
      final notificationsEnabled =
          eventSettings?.notificationsEnabled ?? globalSettings.notificationsEnabled;
      final hapticEnabled = eventSettings?.hapticEnabled ?? globalSettings.hapticEnabled;
      final hapticIntensity =
          eventSettings?.hapticIntensity ?? globalSettings.hapticIntensity;
      final soundEnabled = eventSettings?.soundEnabled ?? globalSettings.soundEnabled;

      // Trigger haptic feedback if enabled
      if (hapticEnabled) {
        await _hapticService.triggerHaptic(hapticIntensity);
      }

      // Show notification if enabled
      if (notificationsEnabled && _initialized) {
        await _showNotification(
          title: 'Event Complete',
          body: '${event.title} has finished',
          soundEnabled: soundEnabled,
        );
      }
    } catch (e) {
      debugPrint('Error handling event completion: $e');
    }
  }

  /// Show a local notification
  Future<void> _showNotification({
    required String title,
    required String body,
    bool soundEnabled = true,
  }) async {
    if (!_initialized || kIsWeb) return;

    // Skip showing notifications on desktop platforms
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      debugPrint('Notification skipped on desktop: $title - $body');
      return;
    }

    try {
      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'event_completion',
        'Event Completions',
        channelDescription: 'Notifications when events complete',
        importance: Importance.high,
        priority: Priority.high,
        playSound: soundEnabled,
        enableVibration: true,
      );

      DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: soundEnabled,
      );

      NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        0, // notification ID
        title,
        body,
        details,
      );
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }
}
