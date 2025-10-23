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
      listener: (context, state) {
        if (state is DeletionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry deletion for all events in the error state
                  for (final series in state.series) {
                    context.read<SeriesBloc>().add(DeleteSeries(series, -1));
                  }
                },
              ),
            ),
          );
        }
      },
      child: BlocBuilder<SeriesBloc, SeriesState>(
        builder: (context, state) {
          // Find the current series from the state to get the latest data
          Series currentSeries = series;
          if (state is SeriesLoaded) {
          // Find the series with the same key
          final updatedSeries = state.series.firstWhere(
            (s) => s.key == series.key,
            orElse: () => series,
          );
          currentSeries = updatedSeries;
        }
        
        return Scaffold(
          appBar: AppBar(
            title: Text(currentSeries.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
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
                onDismissed: () {
                  // Capture the bloc reference before showing snackbar
                  final seriesBloc = context.read<SeriesBloc>();
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

    showDialog(
      context: context,
      builder: (BuildContext context) {
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
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Capture bloc and navigator references before async operations
                final seriesBloc = context.read<SeriesBloc>();
                final navigator = Navigator.of(context);
                
                final event = Event.fromDuration(
                  title: titleController.text,
                  duration: Duration(
                    seconds: int.parse(durationController.text),
                  ),
                );
                // Get the events box and add the event to it first
                final eventsBox = await Hive.openBox<Event>('events');
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
  }
}
