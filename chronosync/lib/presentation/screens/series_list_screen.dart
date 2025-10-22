import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/logic/series_bloc/series_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:chronosync/presentation/screens/event_list_screen.dart';

class SeriesListScreen extends StatelessWidget {
  const SeriesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series'),
      ),
      body: BlocBuilder<SeriesBloc, SeriesState>(
        builder: (context, state) {
          if (state is SeriesInitial) {
            context.read<SeriesBloc>().add(LoadSeries());
            return const Center(child: CircularProgressIndicator());
          }
          if (state is SeriesLoaded) {
            return ListView.builder(
              itemCount: state.series.length,
              itemBuilder: (context, index) {
                final series = state.series[index];
                return ListTile(
                  title: Text(series.title),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EventListScreen(series: series),
                      ),
                    );
                  },
                );
              },
            );
          }
          return const Center(child: Text('Something went wrong.'));
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddSeriesDialog(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddSeriesDialog(BuildContext context) {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Series'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(hintText: 'Series Title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final series = Series(
                  title: titleController.text,
                  events: HiveList(Hive.box<Event>('events')),
                );
                context.read<SeriesBloc>().add(AddSeries(series));
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}
