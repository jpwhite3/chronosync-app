part of 'series_bloc.dart';

abstract class SeriesEvent extends Equatable {
  const SeriesEvent();

  @override
  List<Object> get props => <Object>[];
}

class LoadSeries extends SeriesEvent {}

class AddSeries extends SeriesEvent {
  final Series series;

  const AddSeries(this.series);

  @override
  List<Object> get props => <Object>[series];
}
