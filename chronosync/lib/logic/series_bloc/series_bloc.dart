import 'package:bloc/bloc.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/repositories/series_repository.dart';
import 'package:equatable/equatable.dart';

part 'series_event.dart';
part 'series_state.dart';

class SeriesBloc extends Bloc<SeriesEvent, SeriesState> {
  final SeriesRepository _seriesRepository;

  SeriesBloc(this._seriesRepository) : super(SeriesInitial()) {
    on<LoadSeries>(_onLoadSeries);
    on<AddSeries>(_onAddSeries);
  }

  void _onLoadSeries(LoadSeries event, Emitter<SeriesState> emit) {
    final List<Series> series = _seriesRepository.getAllSeries();
    emit(SeriesLoaded(series));
  }

  Future<void> _onAddSeries(AddSeries event, Emitter<SeriesState> emit) async {
    await _seriesRepository.addSeries(event.series);
    add(LoadSeries());
  }
}
