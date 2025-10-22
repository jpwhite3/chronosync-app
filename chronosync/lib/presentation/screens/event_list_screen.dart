import 'package:chronosync/data/models/series.dart';
import 'package:flutter/material.dart';
import 'package:chronosync/logic/series_bloc/series_bloc.dart';

class EventListScreen extends StatelessWidget {
  final Series series;

  const EventListScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SeriesBloc, SeriesState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(series.title),
          ),
          body: ListView.builder(
            itemCount: series.events.length,
            itemBuilder: (context, index) {
              final event = series.events[index];
              return ListTile(
                title: Text(event.title),
                subtitle: Text(event.duration.toString()),
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              _showAddEventDialog(context, series);
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _showAddEventDialog(BuildContext context, Series series) {
    final titleController = TextEditingController();
    final durationController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Event'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final event = Event(
                  title: titleController.text,
                  duration: Duration(
                    seconds: int.parse(durationController.text),
                  ),
                );
                // This is not the ideal way to do this, but it will work for now.
                // A better solution would be to have a separate BLoC for events.
                series.events.add(event);
                series.save();
                context.read<SeriesBloc>().add(LoadSeries());
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}
