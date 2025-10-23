import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/logic/series_bloc/series_bloc.dart';
import 'package:chronosync/presentation/widgets/dismissible_series_item.dart';
import 'package:chronosync/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

class SeriesListScreen extends StatelessWidget {
  const SeriesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series'),
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
      body: BlocListener<SeriesBloc, SeriesState>(
        listener: (context, state) {
          if (state is DeletionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () {
                    // Retry deletion for all series in the error state
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
          builder: (BuildContext context, SeriesState state) {
            if (state is SeriesInitial) {
              context.read<SeriesBloc>().add(LoadSeries());
              return const Center(child: CircularProgressIndicator());
            }
            if (state is SeriesLoaded) {
            return ListView.builder(
              itemCount: state.series.length,
              itemBuilder: (BuildContext context, int index) {
                final Series series = state.series[index];
                return DismissibleSeriesItem(
                  series: series,
                  index: index,
                  onDismissed: () {
                    context.read<SeriesBloc>().add(
                      DeleteSeries(series, index),
                    );

                    // Show undo snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Series deleted'),
                        duration: const Duration(seconds: 8),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () {
                            context.read<SeriesBloc>().add(
                              UndoDeletion(series.key),
                            );
                          },
                        ),
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
    final TextEditingController titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Create Series'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(hintText: 'Series Title'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final Series series = Series(
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
