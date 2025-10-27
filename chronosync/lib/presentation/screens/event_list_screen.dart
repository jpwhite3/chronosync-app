import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/logic/series_bloc/series_bloc.dart';
import 'package:chronosync/presentation/widgets/dismissible_event_item.dart';
import 'package:chronosync/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

class EventListScreen extends StatelessWidget {
  final Series series;

  const EventListScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SeriesBloc, SeriesState>(
      listener: (BuildContext context, SeriesState state) {
        if (state is DeletionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry deletion for all events in the error state
                  for (final Series series in state.series) {
                    context.read<SeriesBloc>().add(DeleteSeries(series, -1));
                  }
                },
              ),
            ),
          );
        }
      },
      child: BlocBuilder<SeriesBloc, SeriesState>(
        builder: (BuildContext context, SeriesState state) {
          // Find the current series from the state to get the latest data
          Series currentSeries = series;
          if (state is SeriesLoaded) {
          // Find the series with the same key
          final Series updatedSeries = state.series.firstWhere(
            (Series s) => s.key == series.key,
            orElse: () => series,
          );
          currentSeries = updatedSeries;
        }
        
        return Scaffold(
          appBar: AppBar(
            title: Text(currentSeries.title),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (BuildContext context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView.builder(
            itemCount: currentSeries.events.length,
            itemBuilder: (BuildContext context, int index) {
              final Event event = currentSeries.events[index];
              return DismissibleEventItem(
                event: event,
                series: currentSeries,
                index: index,
                onEdit: () {
                  _showEditEventDialog(context, currentSeries, event, index);
                },
                onDismissed: () {
                  // Capture the bloc reference before showing snackbar
                  final SeriesBloc seriesBloc = context.read<SeriesBloc>();
                  final eventKey = event.key;
                  
                  seriesBloc.add(
                    DeleteEvent(event, currentSeries, index),
                  );

                  // Show undo snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Event deleted'),
                      duration: const Duration(seconds: 8),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () {
                          seriesBloc.add(
                            UndoDeletion(eventKey),
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              _showAddEventDialog(context, currentSeries);
            },
            child: const Icon(Icons.add),
          ),
        );
      },
      ),
    );
  }

  void _showAddEventDialog(BuildContext context, Series series) {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController durationController = TextEditingController();
    bool autoProgress = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Add Event'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(hintText: 'Event Title'),
                  ),
                  TextField(
                    controller: durationController,
                    decoration: const InputDecoration(hintText: 'Duration (in seconds)'),
                    keyboardType: TextInputType.number,
                  ),
                  SwitchListTile(
                    title: const Text('Auto-progress'),
                    subtitle: const Text('Auto-advance when time expires'),
                    value: autoProgress,
                    onChanged: (bool value) {
                      setState(() {
                        autoProgress = value;
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    // Validate duration (minimum 1 second)
                    final int duration = int.tryParse(durationController.text) ?? 0;
                    if (duration < 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Event duration must be at least 1 second'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    // Capture bloc and navigator references before async operations
                    final SeriesBloc seriesBloc = context.read<SeriesBloc>();
                    final NavigatorState navigator = Navigator.of(context);
                    
                    final Event event = Event.fromDuration(
                      title: titleController.text,
                      duration: Duration(seconds: duration),
                      autoProgress: autoProgress,
                    );
                    // Get the events box and add the event to it first
                    final Box<Event> eventsBox = await Hive.openBox<Event>('events');
                    await eventsBox.add(event);
                    
                    // Now we can add the event to the series
                    // This is not the ideal way to do this, but it will work for now.
                    // A better solution would be to have a separate BLoC for events.
                    series.events.add(event);
                    await series.save();
                    
                    // Use captured references
                    seriesBloc.add(LoadSeries());
                    navigator.pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditEventDialog(BuildContext context, Series series, Event event, int index) {
    final TextEditingController titleController = TextEditingController(text: event.title);
    final TextEditingController durationController = TextEditingController(text: event.durationInSeconds.toString());
    bool autoProgress = event.autoProgress;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Edit Event'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(hintText: 'Event Title'),
                  ),
                  TextField(
                    controller: durationController,
                    decoration: const InputDecoration(hintText: 'Duration (in seconds)'),
                    keyboardType: TextInputType.number,
                  ),
                  SwitchListTile(
                    title: const Text('Auto-progress'),
                    subtitle: const Text('Auto-advance when time expires'),
                    value: autoProgress,
                    onChanged: (bool value) {
                      setState(() {
                        autoProgress = value;
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    // Validate duration (minimum 1 second)
                    final int duration = int.tryParse(durationController.text) ?? 0;
                    if (duration < 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Event duration must be at least 1 second'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    // Capture bloc and navigator references before async operations
                    final SeriesBloc seriesBloc = context.read<SeriesBloc>();
                    final NavigatorState navigator = Navigator.of(context);
                    
                    // Update event properties
                    event.title = titleController.text;
                    event.durationInSeconds = duration;
                    event.autoProgress = autoProgress;
                    
                    // Save the event and series
                    await event.save();
                    await series.save();
                    
                    // Use captured references
                    seriesBloc.add(LoadSeries());
                    navigator.pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
