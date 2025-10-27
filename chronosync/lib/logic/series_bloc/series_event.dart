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

class DeleteEvent extends SeriesEvent {
  final Event event;
  final Series series;
  final int index;

  const DeleteEvent(this.event, this.series, this.index);

  @override
  List<Object> get props => <Object>[event, series, index];
}

class UndoDeletion extends SeriesEvent {
  final dynamic itemKey;

  const UndoDeletion(this.itemKey);

  @override
  List<Object> get props => <Object>[itemKey];
}

class ConfirmPermanentDeletion extends SeriesEvent {
  final dynamic itemKey;

  const ConfirmPermanentDeletion(this.itemKey);

  @override
  List<Object> get props => <Object>[itemKey];
}

class DeleteSeries extends SeriesEvent {
  final Series series;
  final int index;

  const DeleteSeries(this.series, this.index);

  @override
  List<Object> get props => <Object>[series, index];
}
