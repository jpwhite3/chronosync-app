import 'package:bloc/bloc.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/data/repositories/preferences_repository.dart';
import 'package:chronosync/logic/settings_cubit/settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final PreferencesRepository _repository;

  SettingsCubit(this._repository)
      : super(SettingsLoaded(
          swipeDirection: _repository.getSwipeDirection(),
          autoProgressAudioEnabled: _repository.getAutoProgressAudioEnabled(),
        ));

  void setSwipeDirection(SwipeDirection direction) {
    _repository.saveSwipeDirection(direction);
    final currentState = state as SettingsLoaded;
    emit(currentState.copyWith(swipeDirection: direction));
  }

  void toggleAutoProgressAudio(bool enabled) {
    _repository.saveAutoProgressAudioEnabled(enabled);
    final currentState = state as SettingsLoaded;
    emit(currentState.copyWith(autoProgressAudioEnabled: enabled));
  }

  SwipeDirection getSwipeDirection() {
    return (state as SettingsLoaded).swipeDirection;
  }

  bool getAutoProgressAudioEnabled() {
    return (state as SettingsLoaded).autoProgressAudioEnabled;
  }
}
