import 'package:equatable/equatable.dart';
import '../../data/models/global_notification_settings.dart';

/// States for NotificationSettingsBloc
abstract class NotificationSettingsState extends Equatable {
  const NotificationSettingsState();

  @override
  List<Object?> get props => [];
}

/// Initial state (before any settings loaded)
class NotificationSettingsInitial extends NotificationSettingsState {
  const NotificationSettingsInitial();
}

/// Loading settings from repository
class NotificationSettingsLoading extends NotificationSettingsState {
  const NotificationSettingsLoading();
}

/// Settings loaded successfully
class NotificationSettingsLoaded extends NotificationSettingsState {
  final GlobalNotificationSettings settings;
  final bool hasNotificationPermission;

  const NotificationSettingsLoaded({
    required this.settings,
    this.hasNotificationPermission = true,
  });

  @override
  List<Object?> get props => [settings, hasNotificationPermission];

  NotificationSettingsLoaded copyWith({
    GlobalNotificationSettings? settings,
    bool? hasNotificationPermission,
  }) {
    return NotificationSettingsLoaded(
      settings: settings ?? this.settings,
      hasNotificationPermission:
          hasNotificationPermission ?? this.hasNotificationPermission,
    );
  }
}

/// Error loading or saving settings
class NotificationSettingsError extends NotificationSettingsState {
  final String message;

  const NotificationSettingsError(this.message);

  @override
  List<Object?> get props => [message];
}
