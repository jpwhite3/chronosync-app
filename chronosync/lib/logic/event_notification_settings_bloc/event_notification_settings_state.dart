import 'package:equatable/equatable.dart';
import '../../data/models/event.dart';
import '../../data/models/event_notification_settings.dart';

/// States for EventNotificationSettingsBloc
abstract class EventNotificationSettingsState extends Equatable {
  const EventNotificationSettingsState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class EventNotificationSettingsInitial extends EventNotificationSettingsState {
  const EventNotificationSettingsInitial();
}

/// Loading event settings
class EventNotificationSettingsLoading extends EventNotificationSettingsState {
  const EventNotificationSettingsLoading();
}

/// Event settings loaded (may be null = using global)
class EventNotificationSettingsLoaded extends EventNotificationSettingsState {
  final Event event;
  final EventNotificationSettings settings;

  const EventNotificationSettingsLoaded({
    required this.event,
    required this.settings,
  });

  @override
  List<Object?> get props => [event, settings];

  EventNotificationSettingsLoaded copyWith({
    Event? event,
    EventNotificationSettings? settings,
  }) {
    return EventNotificationSettingsLoaded(
      event: event ?? this.event,
      settings: settings ?? this.settings,
    );
  }
}

/// Error loading or saving event settings
class EventNotificationSettingsError extends EventNotificationSettingsState {
  final String message;

  const EventNotificationSettingsError(this.message);

  @override
  List<Object?> get props => [message];
}
