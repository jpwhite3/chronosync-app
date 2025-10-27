import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/logic/settings_cubit/settings_cubit.dart';
import 'package:chronosync/logic/settings_cubit/settings_state.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:chronosync/presentation/widgets/deletion_confirmation_dialog.dart';
import 'package:chronosync/presentation/screens/event_list_screen.dart';
import 'package:chronosync/presentation/screens/live_timer_screen.dart';

class DismissibleSeriesItem extends StatelessWidget {
  final Series series;
  final int index;
  final VoidCallback onDismissed;

  const DismissibleSeriesItem({
    super.key,
    required this.series,
    required this.index,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (BuildContext context, SettingsState settingsState) {
        final SwipeDirection direction = (settingsState as SettingsLoaded).swipeDirection;

        return Dismissible(
          key: Key(series.key.toString()),
          direction: direction.dismissDirection,
          confirmDismiss: (DismissDirection dismissDirection) async {
            // For empty series, allow immediate dismissal
            if (series.events.isEmpty) {
              return true;
            }
            // For non-empty series, show confirmation dialog
            final bool? confirmed = await showDialog<bool>(
              context: context,
              barrierDismissible: true, // Tapping outside dismisses as cancel
              builder: (BuildContext context) {
                return DeletionConfirmationDialog(series: series);
              },
            );
            return confirmed ?? false; // Treat null (dismissed) as cancel
          },
          onDismissed: (DismissDirection direction) => onDismissed(),
          background: Container(
            color: Colors.red,
            alignment: direction == SwipeDirection.ltr
                ? Alignment.centerLeft
                : Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: ListTile(
            title: Text(series.title),
            subtitle: Text('${series.events.length} event(s)'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: series.events.isEmpty
                      ? null
                      : () {
                          // Create LiveTimerBloc and start the timer
                          final LiveTimerBloc liveTimerBloc = LiveTimerBloc();
                          liveTimerBloc.add(StartTimer(series));
                          
                          // Navigate to live timer screen with the BLoC provided
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (BuildContext context) => BlocProvider.value(
                                value: liveTimerBloc,
                                child: const LiveTimerScreen(),
                              ),
                            ),
                          );
                        },
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () {
              // Navigate to event list screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (BuildContext context) => EventListScreen(series: series),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
