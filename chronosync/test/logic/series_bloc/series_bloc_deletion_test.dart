import 'dart:io';

import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/repositories/series_repository.dart';
import 'package:chronosync/logic/series_bloc/series_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temporaryDirectory;
  late Box<Event> eventBox;
  late Box<Series> seriesBox;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'chronosync_series_deletion_',
    );
    Hive.init(temporaryDirectory.path);
    Hive.registerAdapter(EventAdapter());
    Hive.registerAdapter(SeriesAdapter());
  });

  setUp(() async {
    eventBox = await Hive.openBox<Event>('deletion_events');
    seriesBox = await Hive.openBox<Series>('deletion_series');
  });

  tearDown(() async {
    await seriesBox.deleteFromDisk();
    await eventBox.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('confirming an event deletion removes the event from storage', () async {
    final Event event = Event(title: 'Opening', durationInSeconds: 60);
    await eventBox.add(event);
    final HiveList<Event> events = HiveList<Event>(eventBox)..add(event);
    final Series series = Series(title: 'Show', events: events);
    await seriesBox.add(series);
    final dynamic eventKey = event.key;
    final SeriesBloc bloc = SeriesBloc(SeriesRepository(seriesBox));
    final Future<SeriesState> hidden = bloc.stream.firstWhere(
      (SeriesState state) => state is SeriesLoaded,
    );

    bloc.add(DeleteEvent(event, series, 0));
    await hidden;
    bloc.add(ConfirmPermanentDeletion(eventKey));
    await bloc.close();

    expect(eventBox.containsKey(eventKey), isFalse);
  });

  test('undoing concurrent deletions restores original event order', () async {
    final List<Event> events = <Event>[
      Event(title: 'A', durationInSeconds: 60),
      Event(title: 'B', durationInSeconds: 60),
      Event(title: 'C', durationInSeconds: 60),
    ];
    await eventBox.addAll(events);
    final HiveList<Event> eventList = HiveList<Event>(eventBox)..addAll(events);
    final Series series = Series(title: 'Show', events: eventList);
    await seriesBox.add(series);
    final SeriesBloc bloc = SeriesBloc(SeriesRepository(seriesBox));

    Future<void> dispatchAndWait(SeriesEvent event) async {
      final Future<SeriesState> loaded = bloc.stream.firstWhere(
        (SeriesState state) => state is SeriesLoaded,
      );
      bloc.add(event);
      await loaded;
    }

    await dispatchAndWait(DeleteEvent(events[0], series, 0));
    await dispatchAndWait(DeleteEvent(events[1], series, 0));
    await dispatchAndWait(UndoDeletion(events[0].key));
    await dispatchAndWait(UndoDeletion(events[1].key));

    expect(series.events.map((Event event) => event.title), <String>[
      'A',
      'B',
      'C',
    ]);
    await bloc.close();
  });
}
