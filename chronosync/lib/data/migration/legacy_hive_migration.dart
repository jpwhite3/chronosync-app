import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/event_notification_settings.dart';
import 'package:chronosync/data/models/global_notification_settings.dart';
import 'package:chronosync/data/models/haptic_intensity.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:drift/drift.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

const String legacyHiveMigrationKey = 'legacy_hive_migration_v1';
const String legacyPreferencesKey = '0';
const String legacyNotificationSettingsBoxName = 'notification_settings';
const String legacyGlobalNotificationSettingsKey = 'global_settings';
const int _defaultApproachingCueSeconds = 60;
const int _defaultOverdueCueSeconds = 60;

final class LegacyMigrationResult {
  const LegacyMigrationResult({
    required this.wasAlreadyComplete,
    required this.migratedPlanCount,
    required this.migratedStepCount,
  });

  final bool wasAlreadyComplete;
  final int migratedPlanCount;
  final int migratedStepCount;
}

/// Copies the legacy Hive object graph into Drift without modifying Hive.
///
/// The completion marker is written inside the same transaction as the copied
/// plans, so a failed migration is safe to retry on the next launch.
final class LegacyHiveMigration {
  LegacyHiveMigration(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Future<LegacyMigrationResult> migrate(
    Box<Series> seriesBox, {
    Box<UserPreferences>? preferencesBox,
    Box<GlobalNotificationSettings>? notificationSettingsBox,
  }) async {
    final AppMetadataRecord? marker =
        await (_database.select(_database.appMetadataRecords)..where(
              ($AppMetadataRecordsTable table) =>
                  table.key.equals(legacyHiveMigrationKey),
            ))
            .getSingleOrNull();
    if (marker != null) {
      return const LegacyMigrationResult(
        wasAlreadyComplete: true,
        migratedPlanCount: 0,
        migratedStepCount: 0,
      );
    }

    int planCount = 0;
    int stepCount = 0;
    final DateTime migrationTime = DateTime.now().toUtc();
    final _CueProfileValues planCues = _legacyPlanCues(
      preferencesBox?.get(legacyPreferencesKey),
      notificationSettingsBox?.get(legacyGlobalNotificationSettingsKey),
    );

    await _database.transaction(() async {
      for (final Series legacySeries in seriesBox.values) {
        final int eventCount = legacySeries.events.length;
        final int chunkCount = eventCount == 0
            ? 1
            : (eventCount + maxPlanSteps - 1) ~/ maxPlanSteps;
        for (int chunkIndex = 0; chunkIndex < chunkCount; chunkIndex += 1) {
          final String planId = _uuid.v4();
          final String planTitle = _chunkedLegacyPlanTitle(
            legacySeries.title,
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            maximumLength: maximumPlanTitleLength,
          );

          await _database
              .into(_database.planRecords)
              .insert(
                PlanRecordsCompanion.insert(
                  id: planId,
                  title: planTitle,
                  visualCuesEnabled: Value<bool>(planCues.visualEnabled),
                  soundCuesEnabled: Value<bool>(planCues.soundEnabled),
                  hapticCuesEnabled: Value<bool>(planCues.hapticEnabled),
                  createdAtMillis: migrationTime.millisecondsSinceEpoch,
                  updatedAtMillis: migrationTime.millisecondsSinceEpoch,
                ),
              );
          planCount += 1;

          final int firstEventIndex = chunkIndex * maxPlanSteps;
          final int exclusiveEnd = (firstEventIndex + maxPlanSteps).clamp(
            0,
            eventCount,
          );
          for (
            int eventIndex = firstEventIndex;
            eventIndex < exclusiveEnd;
            eventIndex += 1
          ) {
            final Event legacyEvent = legacySeries.events[eventIndex];
            final _CueProfileValues? stepCues = _legacyStepCues(
              legacyEvent.notificationSettings,
              defaults: planCues,
            );
            final String stepTitle = _normalizedLegacyTitle(
              legacyEvent.title,
              fallback: 'Untitled interval',
              maximumLength: maximumStepTitleLength,
            );
            await _database
                .into(_database.stepRecords)
                .insert(
                  StepRecordsCompanion.insert(
                    id: _uuid.v4(),
                    planId: planId,
                    position: eventIndex - firstEventIndex,
                    title: stepTitle,
                    durationSeconds: legacyEvent.durationInSeconds.clamp(
                      1,
                      maxStepDurationSeconds,
                    ),
                    autoAdvance: Value<bool>(legacyEvent.autoProgress),
                    visualCuesEnabled: Value<bool?>(stepCues?.visualEnabled),
                    soundCuesEnabled: Value<bool?>(stepCues?.soundEnabled),
                    hapticCuesEnabled: Value<bool?>(stepCues?.hapticEnabled),
                    approachingCueSeconds: stepCues == null
                        ? const Value<int?>.absent()
                        : const Value<int?>(_defaultApproachingCueSeconds),
                    overdueCueSeconds: stepCues == null
                        ? const Value<int?>.absent()
                        : const Value<int?>(_defaultOverdueCueSeconds),
                  ),
                );
            stepCount += 1;
          }
        }
      }

      await _database
          .into(_database.appMetadataRecords)
          .insert(
            AppMetadataRecordsCompanion.insert(
              key: legacyHiveMigrationKey,
              value: migrationTime.toIso8601String(),
            ),
          );
    });

    return LegacyMigrationResult(
      wasAlreadyComplete: false,
      migratedPlanCount: planCount,
      migratedStepCount: stepCount,
    );
  }

  _CueProfileValues _legacyPlanCues(
    UserPreferences? preferences,
    GlobalNotificationSettings? notifications,
  ) {
    final UserPreferences effectivePreferences =
        preferences ?? UserPreferences();
    final GlobalNotificationSettings effectiveNotifications =
        notifications ?? GlobalNotificationSettings.defaults();
    // CueProfile has one sound switch, while Hive had separate timer-beep and
    // notification-sound switches. Preserve either opt-out when collapsing
    // those settings into the new model.
    return _CueProfileValues(
      visualEnabled: effectiveNotifications.notificationsEnabled,
      soundEnabled:
          effectivePreferences.autoProgressAudioEnabled &&
          effectiveNotifications.soundEnabled,
      hapticEnabled:
          effectiveNotifications.hapticEnabled &&
          effectiveNotifications.hapticIntensity != HapticIntensity.none,
    );
  }

  _CueProfileValues? _legacyStepCues(
    EventNotificationSettings? notifications, {
    required _CueProfileValues defaults,
  }) {
    if (notifications == null ||
        (notifications.notificationsEnabled == null &&
            notifications.soundEnabled == null &&
            notifications.hapticEnabled == null &&
            notifications.hapticIntensity == null)) {
      return null;
    }

    final bool hapticEnabled;
    if (notifications.hapticEnabled == false ||
        notifications.hapticIntensity == HapticIntensity.none) {
      hapticEnabled = false;
    } else if (notifications.hapticIntensity != null) {
      hapticEnabled = true;
    } else {
      hapticEnabled = notifications.hapticEnabled ?? defaults.hapticEnabled;
    }

    return _CueProfileValues(
      visualEnabled:
          notifications.notificationsEnabled ?? defaults.visualEnabled,
      soundEnabled: notifications.soundEnabled ?? defaults.soundEnabled,
      hapticEnabled: hapticEnabled,
    );
  }
}

String _chunkedLegacyPlanTitle(
  String value, {
  required int chunkIndex,
  required int chunkCount,
  required int maximumLength,
}) {
  if (chunkCount == 1) {
    return _normalizedLegacyTitle(
      value,
      fallback: 'Untitled sequence',
      maximumLength: maximumLength,
    );
  }
  final String suffix = ' (${chunkIndex + 1}/$chunkCount)';
  final String base = _normalizedLegacyTitle(
    value,
    fallback: 'Untitled sequence',
    maximumLength: maximumLength - suffix.length,
  );
  return '$base$suffix';
}

String _normalizedLegacyTitle(
  String value, {
  required String fallback,
  required int maximumLength,
}) {
  final String normalized = value.trim();
  final String title = normalized.isEmpty ? fallback : normalized;
  if (title.length <= maximumLength) {
    return title;
  }

  int end = maximumLength;
  final int finalCodeUnit = title.codeUnitAt(end - 1);
  if (finalCodeUnit >= 0xD800 && finalCodeUnit <= 0xDBFF) {
    end -= 1;
  }
  return title.substring(0, end);
}

/// The subset of legacy cue settings representable by the current plan model.
final class _CueProfileValues {
  const _CueProfileValues({
    required this.visualEnabled,
    required this.soundEnabled,
    required this.hapticEnabled,
  });

  final bool visualEnabled;
  final bool soundEnabled;
  final bool hapticEnabled;
}
