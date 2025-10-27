import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/logic/settings_cubit/settings_cubit.dart';
import 'package:chronosync/logic/settings_cubit/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (BuildContext context, SettingsState state) {
          if (state is SettingsLoaded) {
            return ListView(
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Swipe Direction',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                RadioListTile<SwipeDirection>(
                  title: const Text('Left-to-right'),
                  subtitle: const Text('Swipe from left to right to delete'),
                  value: SwipeDirection.ltr,
                  groupValue: state.swipeDirection,
                  onChanged: (SwipeDirection? value) {
                    if (value != null) {
                      context.read<SettingsCubit>().setSwipeDirection(value);
                    }
                  },
                ),
                RadioListTile<SwipeDirection>(
                  title: const Text('Right-to-left'),
                  subtitle: const Text('Swipe from right to left to delete'),
                  value: SwipeDirection.rtl,
                  groupValue: state.swipeDirection,
                  onChanged: (SwipeDirection? value) {
                    if (value != null) {
                      context.read<SettingsCubit>().setSwipeDirection(value);
                    }
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Auto-Progress',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Audio Cue'),
                  subtitle: const Text('Play sound when auto-progressing to next event'),
                  value: state.autoProgressAudioEnabled,
                  onChanged: (bool value) {
                    context.read<SettingsCubit>().toggleAutoProgressAudio(value);
                  },
                ),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
