import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/logic/settings_cubit/settings_cubit.dart';
import 'package:chronosync/logic/settings_cubit/settings_state.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';

class DismissibleEventItem extends StatelessWidget {
  final Event event;
  final Series series;
  final int index;
  final VoidCallback onDismissed;
  final VoidCallback? onEdit;

  const DismissibleEventItem({
    super.key,
    required this.event,
    required this.series,
    required this.index,
    required this.onDismissed,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settingsState) {
        final direction = (settingsState as SettingsLoaded).swipeDirection;

        return Dismissible(
          key: Key(event.key.toString()),
          direction: direction.dismissDirection,
          confirmDismiss: (dismissDirection) async {
            // Check if event is in active timer (if LiveTimerBloc is available)
            try {
              final timerBloc = context.read<LiveTimerBloc>();
              final timerState = timerBloc.state;
              if (timerState is LiveTimerRunning &&
                  timerState.currentEvent.key == event.key) {
                _showActiveTimerDialog(context);
                return false;
              }
            } catch (e) {
              // LiveTimerBloc not available in context - allow deletion
            }
            return true;
          },
          onDismissed: (direction) => onDismissed(),
          background: Container(
            color: Colors.red,
            alignment: direction == SwipeDirection.ltr
                ? Alignment.centerLeft
                : Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: ListTile(
            title: Text(event.title),
            subtitle: Text(_formatDuration(event.duration)),
            trailing: event.autoProgress
                ? const Icon(
                    Icons.play_circle_outline,
                    color: Colors.blue,
                  )
                : null,
            onTap: onEdit,
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  void _showActiveTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot Delete'),
        content: const Text('Event is in use. Stop the timer first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Navigate to timer screen
              // Navigator.pushNamed(context, '/timer');
            },
            child: const Text('Go to Timer'),
          ),
        ],
      ),
    );
  }
}
