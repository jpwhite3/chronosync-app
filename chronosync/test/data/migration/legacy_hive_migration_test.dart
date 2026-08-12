// HiveList remains experimental in Hive 2.x, but it is required to exercise
// compatibility with the legacy persisted data model.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/migration/legacy_hive_migration.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/event_notification_settings.dart';
import 'package:chronosync/data/models/global_notification_settings.dart';
import 'package:chronosync/data/models/haptic_intensity.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Event> eventBox;
  late Box<Series> seriesBox;
  late Box<UserPreferences> preferencesBox;
  late Box<GlobalNotificationSettings> notificationSettingsBox;
  late AppDatabase database;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'chronosync-migration-test-',
    );
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(SeriesAdapter().typeId)) {
      Hive.registerAdapter(SeriesAdapter());
    }
    if (!Hive.isAdapterRegistered(EventAdapter().typeId)) {
      Hive.registerAdapter(EventAdapter());
    }
    if (!Hive.isAdapterRegistered(UserPreferencesAdapter().typeId)) {
      Hive.registerAdapter(UserPreferencesAdapter());
    }
    if (!Hive.isAdapterRegistered(HapticIntensityAdapter().typeId)) {
      Hive.registerAdapter(HapticIntensityAdapter());
    }
    if (!Hive.isAdapterRegistered(GlobalNotificationSettingsAdapter().typeId)) {
      Hive.registerAdapter(GlobalNotificationSettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(EventNotificationSettingsAdapter().typeId)) {
      Hive.registerAdapter(EventNotificationSettingsAdapter());
    }
    eventBox = await Hive.openBox<Event>('events');
    seriesBox = await Hive.openBox<Series>('series');
    preferencesBox = await Hive.openBox<UserPreferences>('preferences');
    notificationSettingsBox = await Hive.openBox<GlobalNotificationSettings>(
      legacyNotificationSettingsBoxName,
    );
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('copies legacy series and events while retaining Hive data', () async {
    final Event doors = Event(
      title: 'Doors',
      durationInSeconds: 300,
      autoProgress: true,
    );
    final Event welcome = Event(title: 'Welcome', durationInSeconds: 120);
    await eventBox.addAll(<Event>[doors, welcome]);
    await seriesBox.add(
      Series(
        title: 'Opening night',
        events: HiveList<Event>(eventBox, objects: <Event>[doors, welcome]),
      ),
    );

    final LegacyMigrationResult result = await LegacyHiveMigration(
      database,
    ).migrate(seriesBox);
    final List<Plan> plans = await DriftPlanRepository(database).getAllPlans();

    expect(result.wasAlreadyComplete, isFalse);
    expect(result.migratedPlanCount, 1);
    expect(result.migratedStepCount, 2);
    expect(plans.single.title, 'Opening night');
    expect(plans.single.steps.map((Step step) => step.title), <String>[
      'Doors',
      'Welcome',
    ]);
    expect(plans.single.steps.first.autoAdvance, isTrue);
    expect(seriesBox.length, 1, reason: 'legacy data is retained for rollback');
    expect(eventBox.length, 2);
  });

  test('normalizes legacy titles at the new database boundaries', () async {
    final String maximumPlanTitle = List<String>.filled(160, 'P').join();
    final String oversizedPlanTitle = List<String>.filled(161, 'Q').join();
    final String maximumStepTitle = List<String>.filled(240, 'S').join();
    final String oversizedStepTitle = List<String>.filled(241, 'T').join();
    final Event boundaryStep = Event(
      title: maximumStepTitle,
      durationInSeconds: 60,
    );
    final Event oversizedStep = Event(
      title: oversizedStepTitle,
      durationInSeconds: 60,
    );
    await eventBox.addAll(<Event>[boundaryStep, oversizedStep]);
    await seriesBox.addAll(<Series>[
      Series(
        title: maximumPlanTitle,
        events: HiveList<Event>(eventBox, objects: <Event>[boundaryStep]),
      ),
      Series(
        title: oversizedPlanTitle,
        events: HiveList<Event>(eventBox, objects: <Event>[oversizedStep]),
      ),
    ]);

    await LegacyHiveMigration(database).migrate(seriesBox);
    final List<Plan> plans = await DriftPlanRepository(database).getAllPlans();
    final Plan boundaryPlan = plans.singleWhere(
      (Plan plan) => plan.title.startsWith('P'),
    );
    final Plan truncatedPlan = plans.singleWhere(
      (Plan plan) => plan.title.startsWith('Q'),
    );

    expect(boundaryPlan.title, maximumPlanTitle);
    expect(boundaryPlan.steps.single.title, maximumStepTitle);
    expect(truncatedPlan.title, oversizedPlanTitle.substring(0, 160));
    expect(
      truncatedPlan.steps.single.title,
      oversizedStepTitle.substring(0, 240),
    );
  });

  test('splits legacy series that exceed the 250-step plan limit', () async {
    final List<Event> legacyEvents = List<Event>.generate(
      maxPlanSteps + 1,
      (int index) =>
          Event(title: 'Legacy step ${index + 1}', durationInSeconds: 60),
    );
    await eventBox.addAll(legacyEvents);
    await seriesBox.add(
      Series(
        title: 'All-day production',
        events: HiveList<Event>(eventBox, objects: legacyEvents),
      ),
    );

    final LegacyMigrationResult result = await LegacyHiveMigration(
      database,
    ).migrate(seriesBox);
    final List<Plan> plans = List<Plan>.of(
      await DriftPlanRepository(database).getAllPlans(),
    )..sort((Plan left, Plan right) => left.title.compareTo(right.title));

    expect(result.migratedPlanCount, 2);
    expect(result.migratedStepCount, maxPlanSteps + 1);
    expect(plans.map((Plan plan) => plan.title), <String>[
      'All-day production (1/2)',
      'All-day production (2/2)',
    ]);
    expect(plans.first.steps, hasLength(maxPlanSteps));
    expect(plans.last.steps.single.title, 'Legacy step ${maxPlanSteps + 1}');
    expect(
      plans.expand((Plan plan) => plan.steps).map((Step step) => step.title),
      List<String>.generate(
        maxPlanSteps + 1,
        (int index) => 'Legacy step ${index + 1}',
      ),
    );
  });

  test('preserves representable legacy cue and audio preferences', () async {
    await preferencesBox.put(
      legacyPreferencesKey,
      UserPreferences(autoProgressAudioEnabled: false),
    );
    const GlobalNotificationSettings globalSettings =
        GlobalNotificationSettings(
          notificationsEnabled: false,
          hapticEnabled: true,
          hapticIntensity: HapticIntensity.medium,
          soundEnabled: true,
          customSoundPath: 'legacy-global.aiff',
        );
    await notificationSettingsBox.put(
      legacyGlobalNotificationSettingsKey,
      globalSettings,
    );

    final Event explicitCues = Event(
      title: 'Explicit cues',
      durationInSeconds: 90,
      notificationSettings: const EventNotificationSettings(
        notificationsEnabled: true,
        hapticEnabled: true,
        hapticIntensity: HapticIntensity.strong,
        soundEnabled: true,
        customSoundPath: 'legacy-step.aiff',
      ),
    );
    final Event noHaptic = Event(
      title: 'No haptic',
      durationInSeconds: 45,
      notificationSettings: const EventNotificationSettings(
        hapticIntensity: HapticIntensity.none,
      ),
    );
    final Event customSoundOnly = Event(
      title: 'Custom sound only',
      durationInSeconds: 30,
      notificationSettings: const EventNotificationSettings(
        customSoundPath: 'unrepresentable.aiff',
      ),
    );
    final Event intensityOnly = Event(
      title: 'Strong haptic only',
      durationInSeconds: 30,
      notificationSettings: const EventNotificationSettings(
        hapticIntensity: HapticIntensity.strong,
      ),
    );
    await eventBox.addAll(<Event>[
      explicitCues,
      noHaptic,
      customSoundOnly,
      intensityOnly,
    ]);
    await seriesBox.add(
      Series(
        title: 'Cue migration',
        events: HiveList<Event>(
          eventBox,
          objects: <Event>[
            explicitCues,
            noHaptic,
            customSoundOnly,
            intensityOnly,
          ],
        ),
      ),
    );

    await LegacyHiveMigration(database).migrate(
      seriesBox,
      preferencesBox: preferencesBox,
      notificationSettingsBox: notificationSettingsBox,
    );
    final Plan plan = (await DriftPlanRepository(
      database,
    ).getAllPlans()).single;

    expect(
      plan.defaultCueProfile,
      CueProfile(
        visualEnabled: false,
        soundEnabled: false,
        hapticEnabled: true,
      ),
      reason: 'the unified sound toggle honors the legacy audio opt-out',
    );
    expect(
      plan.steps[0].cueOverride,
      CueProfile(visualEnabled: true, soundEnabled: true, hapticEnabled: true),
    );
    expect(
      plan.steps[1].cueOverride,
      CueProfile(
        visualEnabled: false,
        soundEnabled: false,
        hapticEnabled: false,
      ),
      reason: 'a legacy haptic intensity of none is representable as disabled',
    );
    expect(
      plan.steps[2].cueOverride,
      isNull,
      reason: 'custom sound files have no CueProfile representation',
    );
    expect(
      plan.steps[3].cueOverride,
      CueProfile(
        visualEnabled: false,
        soundEnabled: false,
        hapticEnabled: true,
      ),
      reason: 'a non-none legacy intensity represents an enabled haptic cue',
    );

    expect(preferencesBox.length, 1);
    expect(
      preferencesBox.get(legacyPreferencesKey)?.autoProgressAudioEnabled,
      isFalse,
    );
    expect(notificationSettingsBox.length, 1);
    expect(
      notificationSettingsBox.get(legacyGlobalNotificationSettingsKey),
      globalSettings,
    );
    expect(seriesBox.length, 1);
    expect(eventBox.length, 4);
    expect(
      eventBox.getAt(0)?.notificationSettings?.customSoundPath,
      'legacy-step.aiff',
    );
  });

  test('preserves a disabled global sound setting', () async {
    await preferencesBox.put(
      legacyPreferencesKey,
      UserPreferences(autoProgressAudioEnabled: true),
    );
    await notificationSettingsBox.put(
      legacyGlobalNotificationSettingsKey,
      const GlobalNotificationSettings(soundEnabled: false),
    );
    final Event event = Event(title: 'Quiet step', durationInSeconds: 30);
    await eventBox.add(event);
    await seriesBox.add(
      Series(
        title: 'Quiet plan',
        events: HiveList<Event>(eventBox, objects: <Event>[event]),
      ),
    );

    await LegacyHiveMigration(database).migrate(
      seriesBox,
      preferencesBox: preferencesBox,
      notificationSettingsBox: notificationSettingsBox,
    );
    final Plan plan = (await DriftPlanRepository(
      database,
    ).getAllPlans()).single;

    expect(plan.defaultCueProfile.soundEnabled, isFalse);
    expect(preferencesBox.length, 1);
    expect(notificationSettingsBox.length, 1);
  });

  test('writes an idempotent completion marker', () async {
    final LegacyHiveMigration migration = LegacyHiveMigration(database);

    final LegacyMigrationResult first = await migration.migrate(seriesBox);
    final LegacyMigrationResult second = await migration.migrate(seriesBox);

    expect(first.wasAlreadyComplete, isFalse);
    expect(second.wasAlreadyComplete, isTrue);
    expect(
      await database.select(database.appMetadataRecords).get(),
      hasLength(1),
    );
  });
}
