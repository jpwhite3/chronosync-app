import 'package:equatable/equatable.dart';
import 'package:chronosync/data/models/user_preferences.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();
  
  @override
  List<Object> get props => [];
}

class SettingsLoaded extends SettingsState {
  final SwipeDirection swipeDirection;

  const SettingsLoaded(this.swipeDirection);

  @override
  List<Object> get props => [swipeDirection];
}
