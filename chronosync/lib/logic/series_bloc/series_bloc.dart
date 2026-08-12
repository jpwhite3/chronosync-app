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
  final Map<dynamic, Timer> _pendingDeletions = <dynamic, Timer>{};
  final Map<dynamic, _DeletionContext> _deletionContexts =
      <dynamic, _DeletionContext>{};
  final Map<dynamic, Future<void>> _finalizationTasks =
      <dynamic, Future<void>>{};

  SeriesBloc(this._seriesRepository) : super(SeriesInitial()) {
    on<LoadSeries>(_onLoadSeries);
    on<AddSeries>(_onAddSeries);
    on<DeleteEvent>(_onDeleteEvent);
    on<DeleteSeries>(_onDeleteSeries);
    on<UndoDeletion>(_onUndoDeletion);
    on<ConfirmPermanentDeletion>(_onConfirmPermanentDeletion);
  }

  void _onLoadSeries(LoadSeries event, Emitter<SeriesState> emit) {
    final List<Series> allSeries = _seriesRepository.getAllSeries();
    // Filter out series that are pending deletion
    final List<Series> visibleSeries = allSeries
        .where((Series s) => !_pendingDeletions.containsKey(s.key))
        .toList();
    emit(SeriesLoaded(visibleSeries));
  }

  Future<void> _onAddSeries(AddSeries event, Emitter<SeriesState> emit) async {
    await _seriesRepository.addSeries(event.series);
    add(LoadSeries());
  }

  Future<void> _onDeleteEvent(
    DeleteEvent event,
    Emitter<SeriesState> emit,
  ) async {
    try {
      // Cancel existing timer if present (rapid deletion handling)
      _pendingDeletions[event.event.key]?.cancel();

      final int originalIndex = _originalEventIndex(
        parentSeries: event.series,
        visibleIndex: event.index,
      );
      // Store deletion context for undo
      _deletionContexts[event.event.key] = _DeletionContext(
        event: event.event,
        parentSeries: event.series,
        index: originalIndex,
      );

      // Remove from series.events HiveList
      event.series.events.remove(event.event);
      await event.series.save();

      // Start undo timer
      _pendingDeletions[event.event.key] = Timer(
        const Duration(seconds: 8),
        () {
          _finalizeDeletion(event.event.key).onError((Object _, StackTrace _) {
            // Keep the context available for an explicit retry or undo.
          });
        },
      );

      add(LoadSeries());
    } catch (e) {
      // Auto-retry once
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        // Cancel existing timer if present
        _pendingDeletions[event.event.key]?.cancel();

        final int originalIndex =
            _deletionContexts[event.event.key]?.index ??
            _originalEventIndex(
              parentSeries: event.series,
              visibleIndex: event.index,
            );
        // Store deletion context for undo (in retry path too)
        _deletionContexts[event.event.key] = _DeletionContext(
          event: event.event,
          parentSeries: event.series,
          index: originalIndex,
        );

        event.series.events.remove(event.event);
        await event.series.save();

        _pendingDeletions[event.event.key] = Timer(
          const Duration(seconds: 8),
          () {
            _finalizeDeletion(event.event.key).onError((
              Object _,
              StackTrace _,
            ) {
              // Keep the context available for an explicit retry or undo.
            });
          },
        );

        add(LoadSeries());
      } catch (retryError) {
        emit(
          DeletionError(
            'Failed to delete. Tap to retry.',
            _seriesRepository.getAllSeries(),
          ),
        );
      }
    }
  }

  Future<void> _onUndoDeletion(
    UndoDeletion event,
    Emitter<SeriesState> emit,
  ) async {
    final Timer? timer = _pendingDeletions[event.itemKey];
    final _DeletionContext? context = _deletionContexts[event.itemKey];

    if (timer != null && context != null) {
      timer.cancel();
      _pendingDeletions.remove(event.itemKey);
      _deletionContexts.remove(event.itemKey);

      // Restore the event to its parent series
      if (context.event != null && context.parentSeries != null) {
        final int pendingBefore = _deletionContexts.values.where((
          _DeletionContext other,
        ) {
          return other.event != null &&
              _sameSeries(other.parentSeries, context.parentSeries) &&
              other.index < context.index;
        }).length;
        final int insertionIndex = (context.index - pendingBefore).clamp(
          0,
          context.parentSeries!.events.length,
        );
        context.parentSeries!.events.insert(insertionIndex, context.event!);
        await context.parentSeries!.save();
      }

      // Restore the series (if it was a series deletion)
      // Since we never actually deleted it, it will show up again when we reload
      // after removing it from _pendingDeletions (which happens above)

      add(LoadSeries());
    }
  }

  Future<void> _onDeleteSeries(
    DeleteSeries event,
    Emitter<SeriesState> emit,
  ) async {
    try {
      // Cancel existing timer if present (rapid deletion handling)
      _pendingDeletions[event.series.key]?.cancel();

      // Store deletion context for undo
      _deletionContexts[event.series.key] = _DeletionContext(
        series: event.series,
        index: event.index,
      );

      // DON'T delete immediately - wait for timer to expire or undo
      // This allows undo to work properly

      // Start undo timer - only permanently delete when timer expires
      _pendingDeletions[event.series.key] = Timer(
        const Duration(seconds: 8),
        () {
          _finalizeDeletion(event.series.key).onError((Object _, StackTrace _) {
            // Keep the context available for an explicit retry or undo.
          });
        },
      );

      add(LoadSeries());
    } catch (e) {
      // Auto-retry once
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        // Cancel existing timer if present
        _pendingDeletions[event.series.key]?.cancel();

        // Store deletion context for undo (retry path)
        _deletionContexts[event.series.key] = _DeletionContext(
          series: event.series,
          index: event.index,
        );

        // DON'T delete immediately in retry path either

        _pendingDeletions[event.series.key] = Timer(
          const Duration(seconds: 8),
          () {
            _finalizeDeletion(event.series.key).onError((
              Object _,
              StackTrace _,
            ) {
              // Keep the context available for an explicit retry or undo.
            });
          },
        );

        add(LoadSeries());
      } catch (retryError) {
        emit(
          DeletionError(
            'Failed to delete. Tap to retry.',
            _seriesRepository.getAllSeries(),
          ),
        );
      }
    }
  }

  Future<void> _onConfirmPermanentDeletion(
    ConfirmPermanentDeletion event,
    Emitter<SeriesState> emit,
  ) async {
    final Timer? timer = _pendingDeletions[event.itemKey];
    if (timer != null) {
      timer.cancel();
      try {
        await _finalizeDeletion(event.itemKey);
      } on Object {
        emit(
          DeletionError(
            'Failed to delete. Tap to retry.',
            _seriesRepository.getAllSeries(),
          ),
        );
      }
    }
  }

  int _originalEventIndex({
    required Series parentSeries,
    required int visibleIndex,
  }) {
    int originalIndex = visibleIndex;
    while (true) {
      final int pendingBeforeOrAt = _deletionContexts.values.where((
        _DeletionContext context,
      ) {
        return context.event != null &&
            _sameSeries(context.parentSeries, parentSeries) &&
            context.index <= originalIndex;
      }).length;
      final int candidate = visibleIndex + pendingBeforeOrAt;
      if (candidate == originalIndex) {
        return originalIndex;
      }
      originalIndex = candidate;
    }
  }

  bool _sameSeries(Series? left, Series? right) {
    if (identical(left, right)) {
      return true;
    }
    return left != null &&
        right != null &&
        left.key != null &&
        left.key == right.key;
  }

  Future<void> _finalizeDeletion(dynamic itemKey) {
    final Future<void>? active = _finalizationTasks[itemKey];
    if (active != null) {
      return active;
    }
    final Future<void> task = _performFinalDeletion(itemKey);
    _finalizationTasks[itemKey] = task;
    return task.whenComplete(() {
      if (identical(_finalizationTasks[itemKey], task)) {
        _finalizationTasks.remove(itemKey);
      }
    });
  }

  Future<void> _performFinalDeletion(dynamic itemKey) async {
    final _DeletionContext? context = _deletionContexts[itemKey];
    if (context == null) {
      return;
    }
    final Event? deletedEvent = context.event;
    final Series? deletedSeries = context.series;
    if (deletedEvent != null) {
      await deletedEvent.delete();
    } else if (deletedSeries != null) {
      for (final Event event in List<Event>.of(deletedSeries.events)) {
        await event.delete();
      }
      await deletedSeries.delete();
    }
    _pendingDeletions.remove(itemKey)?.cancel();
    _deletionContexts.remove(itemKey);

    if (!_validateDataConsistency() && !isClosed) {
      add(LoadSeries());
    }
  }

  /// Validates data consistency between series.events HiveList and events box
  bool _validateDataConsistency() {
    try {
      final List<Series> allSeries = _seriesRepository.getAllSeries();

      for (final Series series in allSeries) {
        // Check that all events in series.events HiveList are valid
        for (final Event event in series.events) {
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
  Future<void> close() async {
    // Cancel all pending timers
    for (final Timer timer in _pendingDeletions.values) {
      timer.cancel();
    }
    await super.close();
    await Future.wait<void>(
      _deletionContexts.keys.toList(growable: false).map(_finalizeDeletion),
    );
  }
}

/// Helper class to store deletion context for undo functionality
class _DeletionContext {
  final Event? event;
  final Series? series;
  final Series? parentSeries;
  final int index;

  _DeletionContext({
    this.event,
    this.series,
    this.parentSeries,
    required this.index,
  });
}
