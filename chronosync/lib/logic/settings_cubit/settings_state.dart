import 'package:equatable/equatable.dart';
import 'package:chronosync/data/models/user_preferences.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();
  
  @override
  List<Object> get props => <Object>[];
}

class SettingsLoaded extends SettingsState {
  final SwipeDirection swipeDirection;
  final bool autoProgressAudioEnabled;

  const SettingsLoaded({
    required this.swipeDirection,
    this.autoProgressAudioEnabled = true,
  });

  @override
  List<Object> get props => <Object>[swipeDirection, autoProgressAudioEnabled];
  
  SettingsLoaded copyWith({
    SwipeDirection? swipeDirection,
    bool? autoProgressAudioEnabled,
  }) {
    return SettingsLoaded(
      swipeDirection: swipeDirection ?? this.swipeDirection,
      autoProgressAudioEnabled: autoProgressAudioEnabled ?? this.autoProgressAudioEnabled,
    );
  }
}
