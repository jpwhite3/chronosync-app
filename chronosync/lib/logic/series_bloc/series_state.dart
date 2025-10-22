part of 'series_bloc.dart';

abstract class SeriesState extends Equatable {
  const SeriesState();

  @override
  List<Object> get props => <Object>[];
}

class SeriesInitial extends SeriesState {}

class SeriesLoaded extends SeriesState {
  final List<Series> series;

  const SeriesLoaded(this.series);

  @override
  List<Object> get props => <Object>[series];
}
