import 'package:hive/hive.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/event.dart';

class SeriesRepository {
  final Box<Series> _seriesBox;

  SeriesRepository(this._seriesBox);

  Future<void> addSeries(Series series) async {
    await _seriesBox.add(series);
  }

  Future<void> updateSeries(int key, Series series) async {
    await _seriesBox.put(key, series);
  }

  Future<void> deleteSeries(int key) async {
    await _seriesBox.delete(key);
  }

  List<Series> getAllSeries() {
    return _seriesBox.values.toList();
  }

  Future<void> addEventToSeries(int seriesKey, Event event) async {
    final series = _seriesBox.get(seriesKey);
    if (series != null) {
      series.events.add(event);
      await series.save();
    }
  }
}
