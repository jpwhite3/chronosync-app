part of 'series_bloc.dart';

abstract class SeriesState extends Equatable {
  const SeriesState();

  @override
  List<Object> get props => <Object>[];
}

class SeriesInitial extends SeriesState {}

class SeriesLoaded extends SeriesState {
  final List<Series> series;
  final Object _identity = Object();

  SeriesLoaded(this.series);

  @override
  List<Object> get props => <Object>[series, _identity];
}

class SeriesDeletionPending extends SeriesState {
  final List<Series> series;
  final Map<dynamic, dynamic> pendingDeletions;

  const SeriesDeletionPending(this.series, this.pendingDeletions);

  @override
  List<Object> get props => [series, pendingDeletions];
}

class DeletionError extends SeriesState {
  final String message;
  final List<Series> series;

  const DeletionError(this.message, this.series);

  @override
  List<Object> get props => [message, series];
}
