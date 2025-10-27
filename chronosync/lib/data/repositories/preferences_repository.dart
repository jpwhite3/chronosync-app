import 'package:hive/hive.dart';
import 'package:chronosync/data/models/user_preferences.dart';

class PreferencesRepository {
  final Box<UserPreferences> _box;

  PreferencesRepository(this._box);

  UserPreferences getPreferences() {
    return _box.get('0') ?? UserPreferences();
  }

  Future<void> saveSwipeDirection(SwipeDirection direction) async {
    final UserPreferences prefs = getPreferences();
    prefs.swipeDirection = direction.value;
    await prefs.save();
  }

  SwipeDirection getSwipeDirection() {
    return getPreferences().swipeDirectionEnum;
  }

  Future<void> saveAutoProgressAudioEnabled(bool enabled) async {
    final UserPreferences prefs = getPreferences();
    prefs.autoProgressAudioEnabled = enabled;
    await prefs.save();
  }

  bool getAutoProgressAudioEnabled() {
    return getPreferences().autoProgressAudioEnabled;
  }
}
