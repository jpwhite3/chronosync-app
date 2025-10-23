import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/repositories/series_repository.dart';
import 'package:equatable/equatable.dart';

part 'series_event.dart';
part 'series_state.dart';

class SeriesBloc extends Bloc<SeriesEvent, SeriesState> {
  final SeriesRepository _seriesRepository;
  final Map<dynamic, Timer> _pendingDeletions = {};

  SeriesBloc(this._seriesRepository) : super(SeriesInitial()) {
    on<LoadSeries>(_onLoadSeries);
    on<AddSeries>(_onAddSeries);
    on<DeleteEvent>(_onDeleteEvent);
    on<DeleteSeries>(_onDeleteSeries);
    on<UndoDeletion>(_onUndoDeletion);
    on<ConfirmPermanentDeletion>(_onConfirmPermanentDeletion);
  }

  void _onLoadSeries(LoadSeries event, Emitter<SeriesState> emit) {
    final List<Series> series = _seriesRepository.getAllSeries();
    emit(SeriesLoaded(series));
  }

  Future<void> _onAddSeries(AddSeries event, Emitter<SeriesState> emit) async {
    await _seriesRepository.addSeries(event.series);
    add(LoadSeries());
  }

  Future<void> _onDeleteEvent(DeleteEvent event, Emitter<SeriesState> emit) async {
    try {
      // Cancel existing timer if present (rapid deletion handling)
      _pendingDeletions[event.event.key]?.cancel();
      
      // Remove from series.events HiveList
      event.series.events.remove(event.event);
      await event.series.save();

      // Start undo timer
      _pendingDeletions[event.event.key] = Timer(
        const Duration(seconds: 8),
        () async {
          await event.event.delete();
          _pendingDeletions.remove(event.event.key);
          
          // Validate data consistency after permanent deletion
          if (!_validateDataConsistency()) {
            add(LoadSeries()); // Refresh to fix any inconsistencies
          }
        },
      );

      add(LoadSeries());
    } catch (e) {
      // Auto-retry once
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        // Cancel existing timer if present
        _pendingDeletions[event.event.key]?.cancel();
        
        event.series.events.remove(event.event);
        await event.series.save();
        
        _pendingDeletions[event.event.key] = Timer(
          const Duration(seconds: 8),
          () async {
            await event.event.delete();
            _pendingDeletions.remove(event.event.key);
          },
        );
        
        add(LoadSeries());
      } catch (retryError) {
        emit(DeletionError('Failed to delete. Tap to retry.', _seriesRepository.getAllSeries()));
      }
    }
  }

  Future<void> _onUndoDeletion(UndoDeletion event, Emitter<SeriesState> emit) async {
    final timer = _pendingDeletions[event.itemKey];
    if (timer != null) {
      timer.cancel();
      _pendingDeletions.remove(event.itemKey);
      add(LoadSeries());
    }
  }

  Future<void> _onDeleteSeries(DeleteSeries event, Emitter<SeriesState> emit) async {
    try {
      // Cancel existing timer if present (rapid deletion handling)
      _pendingDeletions[event.series.key]?.cancel();
      
      // Remove series from repository
      await event.series.delete();

      // Start undo timer
      _pendingDeletions[event.series.key] = Timer(
        const Duration(seconds: 8),
        () {
          _pendingDeletions.remove(event.series.key);
        },
      );

      add(LoadSeries());
    } catch (e) {
      // Auto-retry once
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        // Cancel existing timer if present
        _pendingDeletions[event.series.key]?.cancel();
        
        await event.series.delete();
        
        _pendingDeletions[event.series.key] = Timer(
          const Duration(seconds: 8),
          () {
            _pendingDeletions.remove(event.series.key);
          },
        );
        
        add(LoadSeries());
      } catch (retryError) {
        emit(DeletionError('Failed to delete. Tap to retry.', _seriesRepository.getAllSeries()));
      }
    }
  }

  Future<void> _onConfirmPermanentDeletion(ConfirmPermanentDeletion event, Emitter<SeriesState> emit) async {
    final timer = _pendingDeletions[event.itemKey];
    if (timer != null) {
      timer.cancel();
      _pendingDeletions.remove(event.itemKey);
      
      // If it's a series key, cascade delete all events
      try {
        final allSeries = _seriesRepository.getAllSeries();
        final seriesToDelete = allSeries.where((s) => s.key == event.itemKey).firstOrNull;
        
        if (seriesToDelete != null) {
          // Delete all events in the series
          for (final event in seriesToDelete.events) {
            await event.delete();
          }
          // Delete the series itself
          await seriesToDelete.delete();
        }
      } catch (e) {
        // Log error but don't re-add to pending deletions (zombie state prevention)
      }
    }
  }

  /// Validates data consistency between series.events HiveList and events box
  bool _validateDataConsistency() {
    try {
      final allSeries = _seriesRepository.getAllSeries();
      
      for (final series in allSeries) {
        // Check that all events in series.events HiveList are valid
        for (final event in series.events) {
          if (event.isInBox == false) {
            // Event in HiveList but not in box - inconsistency detected
            return false;
          }
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> close() {
    // Cancel all pending timers
    for (final timer in _pendingDeletions.values) {
      timer.cancel();
    }
    return super.close();
  }
}
