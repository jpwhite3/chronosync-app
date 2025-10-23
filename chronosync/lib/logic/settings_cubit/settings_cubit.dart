import 'package:bloc/bloc.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/data/repositories/preferences_repository.dart';
import 'package:chronosync/logic/settings_cubit/settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final PreferencesRepository _repository;

  SettingsCubit(this._repository)
      : super(SettingsLoaded(_repository.getSwipeDirection()));

  void setSwipeDirection(SwipeDirection direction) {
    _repository.saveSwipeDirection(direction);
    emit(SettingsLoaded(direction));
  }

  SwipeDirection getSwipeDirection() {
    return (state as SettingsLoaded).swipeDirection;
  }
}
