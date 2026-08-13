import 'dart:async';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/core/platform/initial_invitation_uri.dart';
import 'package:chronosync/data/migration/legacy_hive_migration.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/event_notification_settings.dart';
import 'package:chronosync/data/models/global_notification_settings.dart';
import 'package:chronosync/data/models/haptic_intensity.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/data/portability/plan_archive_service.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/data/transports/online_room_service.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/logic/live_session/live_session_controller.dart';
import 'package:chronosync/presentation/screens/history_summary_screen.dart';
import 'package:chronosync/presentation/screens/join_session_dialog.dart';
import 'package:chronosync/presentation/screens/join_session_screen.dart';
import 'package:chronosync/presentation/screens/mvp_app_shell.dart';
import 'package:chronosync/presentation/screens/session_flow_screen.dart';
import 'package:chronosync/presentation/screens/session_recovery_dialog.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChronoSyncBootstrap());
}

typedef AppDependenciesInitializer =
    Future<AppDependencies> Function({ValueChanged<String>? onProgress});

class ChronoSyncBootstrap extends StatefulWidget {
  const ChronoSyncBootstrap({this.dependencyInitializer, super.key});

  final AppDependenciesInitializer? dependencyInitializer;

  @override
  State<ChronoSyncBootstrap> createState() => _ChronoSyncBootstrapState();
}

class _ChronoSyncBootstrapState extends State<ChronoSyncBootstrap> {
  late Future<AppDependencies> _dependencies;
  String _progress = 'Opening local storage…';
  int _initializationAttempt = 0;

  @override
  void initState() {
    super.initState();
    _dependencies = _initializeDependencies();
  }

  Future<AppDependencies> _initializeDependencies() {
    final int attempt = ++_initializationAttempt;
    final AppDependenciesInitializer initialize =
        widget.dependencyInitializer ?? AppDependencies.initialize;
    return initialize(
      onProgress: (String message) {
        if (!mounted || attempt != _initializationAttempt) {
          return;
        }
        _progress = message;
        scheduleMicrotask(() {
          if (mounted && attempt == _initializationAttempt) {
            setState(() {});
          }
        });
      },
    );
  }

  void _retry() {
    setState(() {
      _progress = 'Opening local storage…';
      _dependencies = _initializeDependencies();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDependencies>(
      future: _dependencies,
      builder: (BuildContext context, AsyncSnapshot<AppDependencies> snapshot) {
        if (snapshot.hasData) {
          return MyApp(dependencies: snapshot.data!);
        }
        final bool hasTerminalError =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError;
        return MaterialApp(
          title: 'ChronoSync',
          debugShowCheckedModeBanner: false,
          theme: ChronoTheme.light(),
          darkTheme: ChronoTheme.dark(),
          themeMode: ThemeMode.system,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.timer_outlined,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'ChronoSync',
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 12),
                              if (hasTerminalError) ...<Widget>[
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    'ChronoSync could not open local storage.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Your sequences remain on this device. Try '
                                  'opening them again.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _retry,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                ),
                              ] else ...<Widget>[
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _progress,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

@visibleForTesting
final class AppDependenciesInitializationOverrides {
  const AppDependenciesInitializationOverrides({
    this.initializeHive,
    this.createDatabase,
    this.afterDatabaseCreated,
    this.closeHive,
  });

  final Future<void> Function()? initializeHive;
  final AppDatabase Function()? createDatabase;
  final Future<void> Function(AppDatabase database)? afterDatabaseCreated;
  final Future<void> Function()? closeHive;
}

final class AppDependencies {
  const AppDependencies({
    required this.database,
    required this.identity,
    required this.identityRepository,
    required this.planRepository,
    required this.historyRepository,
    required this.archiveService,
    required this.fileService,
    required this.cueService,
    required this.onlineRoomService,
    required this.recoverableSession,
  });

  final AppDatabase database;
  final DeviceIdentity identity;
  final DeviceIdentityRepository identityRepository;
  final PlanRepository planRepository;
  final SessionHistoryRepository historyRepository;
  final PlanArchiveService archiveService;
  final PortabilityFileService fileService;
  final LiveCueService cueService;
  final OnlineRoomService? onlineRoomService;
  final LiveSession? recoverableSession;

  static Future<AppDependencies> initialize({
    ValueChanged<String>? onProgress,
    @visibleForTesting
    AppDependenciesInitializationOverrides? initializationOverrides,
  }) async {
    AppDatabase? database;
    bool hiveInitializationAttempted = false;
    try {
      onProgress?.call('Opening local storage…');
      hiveInitializationAttempted = true;
      await (initializationOverrides?.initializeHive ?? Hive.initFlutter)();
      _registerLegacyAdapters();
      await Hive.openBox<Event>('events');
      final Box<Series> seriesBox = await Hive.openBox<Series>('series');
      final Box<UserPreferences> preferencesBox =
          await Hive.openBox<UserPreferences>('preferences');
      if (preferencesBox.isEmpty) {
        await preferencesBox.put(legacyPreferencesKey, UserPreferences());
      }
      final Box<GlobalNotificationSettings> notificationSettingsBox =
          await Hive.openBox<GlobalNotificationSettings>(
            legacyNotificationSettingsBoxName,
          );

      onProgress?.call('Migrating sequences safely…');
      database =
          initializationOverrides?.createDatabase?.call() ??
          AppDatabase.defaults();
      await initializationOverrides?.afterDatabaseCreated?.call(database);
      await LegacyHiveMigration(database).migrate(
        seriesBox,
        preferencesBox: preferencesBox,
        notificationSettingsBox: notificationSettingsBox,
      );
      onProgress?.call('Finishing setup…');
      final DeviceIdentityRepository identityRepository =
          DeviceIdentityRepository(database);
      final DeviceIdentity identity = await identityRepository.load();
      final DriftSessionHistoryRepository historyRepository =
          DriftSessionHistoryRepository(database);
      final LiveSession? recoverableSession = await historyRepository
          .prepareStartupRecovery(hostDeviceId: identity.deviceId);
      final Uri? relayUri = _relayUri();
      final Uri? joinUri = _joinUri();

      return AppDependencies(
        database: database,
        identity: identity,
        identityRepository: identityRepository,
        planRepository: DriftPlanRepository(database),
        historyRepository: historyRepository,
        archiveService: const PlanArchiveService(),
        fileService: const PortabilityFileService(),
        cueService: LiveCueService(),
        onlineRoomService: relayUri == null || joinUri == null
            ? null
            : OnlineRoomService(relayBaseUri: relayUri, joinBaseUri: joinUri),
        recoverableSession: recoverableSession,
      );
    } on Object catch (error, stackTrace) {
      if (database != null) {
        try {
          await database.close();
        } on Object {
          // Preserve the initialization error that caused cleanup.
        }
      }
      if (hiveInitializationAttempted) {
        try {
          await (initializationOverrides?.closeHive ?? Hive.close)();
        } on Object {
          // Preserve the initialization error that caused cleanup.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static void _registerLegacyAdapters() {
    _registerAdapter<Series>(SeriesAdapter());
    _registerAdapter<Event>(EventAdapter());
    _registerAdapter<UserPreferences>(UserPreferencesAdapter());
    _registerAdapter<HapticIntensity>(HapticIntensityAdapter());
    _registerAdapter<GlobalNotificationSettings>(
      GlobalNotificationSettingsAdapter(),
    );
    _registerAdapter<EventNotificationSettings>(
      EventNotificationSettingsAdapter(),
    );
  }

  static void _registerAdapter<T>(TypeAdapter<T> adapter) {
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter<T>(adapter);
    }
  }

  static Uri? _relayUri() {
    if (defaultRelayUrl.trim().isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(defaultRelayUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static Uri? _joinUri() {
    final Uri? uri;
    if (kIsWeb) {
      uri = Uri.base;
    } else {
      if (defaultWebUrl.trim().isEmpty) {
        return null;
      }
      uri = Uri.tryParse(defaultWebUrl);
    }
    if (uri == null || uri.host.isEmpty || (!kIsWeb && uri.hasFragment)) {
      return null;
    }
    if (uri.scheme == 'https') {
      return _withoutQueryOrFragment(uri);
    }
    if (kIsWeb && uri.scheme == 'http' && _isLoopbackHost(uri.host)) {
      return _withoutQueryOrFragment(uri);
    }
    return null;
  }

  static bool _isLoopbackHost(String host) {
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  Future<void> dispose() async {
    onlineRoomService?.close();
    await cueService.dispose();
    await database.close();
    await Hive.close();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Invitation? _initialInvitation;
  LiveSession? _pendingRecovery;
  bool _startupFlowScheduled = false;

  @override
  void initState() {
    super.initState();
    _initialInvitation = _invitationFromCurrentUrl();
    _pendingRecovery = widget.dependencies.recoverableSession;
  }

  @override
  void dispose() {
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppDependencies dependencies = widget.dependencies;
    if ((_initialInvitation != null || _pendingRecovery != null) &&
        !_startupFlowScheduled) {
      _startupFlowScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        unawaited(_runStartupFlow());
      });
    }
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'ChronoSync',
      debugShowCheckedModeBanner: false,
      theme: ChronoTheme.light(),
      darkTheme: ChronoTheme.dark(),
      themeMode: ThemeMode.system,
      home: MvpAppShell(
        planRepository: dependencies.planRepository,
        historyRepository: dependencies.historyRepository,
        identityRepository: dependencies.identityRepository,
        initialIdentity: dependencies.identity,
        archiveService: dependencies.archiveService,
        fileService: dependencies.fileService,
        onLaunchPlan: _launchPlan,
        onOpenSession: _openSession,
        onJoinSession: _joinSession,
      ),
    );
  }

  Future<void> _runStartupFlow() async {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (!mounted || navigator == null) {
      return;
    }
    final AppDependencies dependencies = widget.dependencies;
    final Invitation? invitation = _initialInvitation;
    _initialInvitation = null;
    if (invitation != null) {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => JoinSessionScreen(
            invitation: invitation,
            localIdentity: dependencies.identity,
            identityRepository: dependencies.identityRepository,
            historyRepository: dependencies.historyRepository,
            cueService: dependencies.cueService,
            fileService: dependencies.fileService,
          ),
        ),
      );
    }
    if (!mounted) {
      return;
    }

    while (mounted && _pendingRecovery != null) {
      if (!navigator.mounted) {
        return;
      }
      final LiveSession session = _pendingRecovery!;
      LiveSessionController? recoveredController;
      DeviceIdentity? currentIdentity;
      final SessionRecoveryChoice? choice = await showSessionRecoveryDialog(
        navigator.context,
        session: session,
        onPrepareResume: () async {
          await dependencies.cueService.unlockAudio();
          currentIdentity = await dependencies.identityRepository.load();
          recoveredController = await LiveSessionController.recoverSolo(
            session: session,
            identity: currentIdentity!,
            historyRepository: dependencies.historyRepository,
            cueService: dependencies.cueService,
          );
        },
      );
      if (!mounted) {
        await recoveredController?.shutdown();
        recoveredController?.dispose();
        return;
      }
      if (choice == null) {
        await recoveredController?.shutdown();
        recoveredController?.dispose();
        return;
      }
      if (choice == SessionRecoveryChoice.discard) {
        try {
          await dependencies.historyRepository.deleteSession(session.id);
          _pendingRecovery = null;
        } on Object {
          _showStartupMessage(
            'The session could not be discarded. Your saved session is still '
            'available.',
          );
        }
        continue;
      }

      final LiveSessionController? controller = recoveredController;
      final DeviceIdentity? identity = currentIdentity;
      if (controller == null || identity == null) {
        _showStartupMessage(
          'The session could not be resumed. Your saved session is still '
          'available.',
        );
        continue;
      }
      if (!navigator.mounted) {
        await controller.shutdown();
        controller.dispose();
        return;
      }
      _pendingRecovery = null;
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => SessionFlowScreen(
            plan: _planFromSnapshot(session.planSnapshot),
            identity: identity,
            historyRepository: dependencies.historyRepository,
            cueService: dependencies.cueService,
            fileService: dependencies.fileService,
            initialController: controller,
            initialTransportLabel: 'Recovered solo session',
          ),
        ),
      );
    }
  }

  void _showStartupMessage(String message) {
    final BuildContext? context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _launchPlan(BuildContext context, Plan plan) async {
    final AppDependencies dependencies = widget.dependencies;
    try {
      final DeviceIdentity currentIdentity = await dependencies
          .identityRepository
          .load();
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => SessionFlowScreen(
            plan: plan,
            identity: currentIdentity,
            historyRepository: dependencies.historyRepository,
            cueService: dependencies.cueService,
            fileService: dependencies.fileService,
            onlineRoomService: dependencies.onlineRoomService,
          ),
        ),
      );
    } on Object {
      if (context.mounted) {
        _showActionMessage(
          context,
          'Could not open the live session. Try again.',
        );
      }
    }
  }

  Future<void> _openSession(BuildContext context, LiveSession session) async {
    final AppDependencies dependencies = widget.dependencies;
    try {
      final DeviceIdentity currentIdentity = await dependencies
          .identityRepository
          .load();
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HistorySummaryScreen(
            session: session,
            hostDisplayName: currentIdentity.displayName,
            fileService: dependencies.fileService,
          ),
        ),
      );
    } on Object {
      if (context.mounted) {
        _showActionMessage(
          context,
          'Could not open the session summary. Try again.',
        );
      }
    }
  }

  Future<void> _joinSession(BuildContext context) async {
    final Invitation? invitation = await showJoinSessionDialog(context);
    if (invitation == null || !context.mounted) {
      return;
    }
    final AppDependencies dependencies = widget.dependencies;
    try {
      final DeviceIdentity currentIdentity = await dependencies
          .identityRepository
          .load();
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => JoinSessionScreen(
            invitation: invitation,
            localIdentity: currentIdentity,
            identityRepository: dependencies.identityRepository,
            historyRepository: dependencies.historyRepository,
            cueService: dependencies.cueService,
            fileService: dependencies.fileService,
          ),
        ),
      );
    } on Object {
      if (context.mounted) {
        _showActionMessage(
          context,
          'Could not prepare this device to join. Try again.',
        );
      }
    }
  }

  void _showActionMessage(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Invitation? _invitationFromCurrentUrl() {
    final Uri currentUri = initialInvitationUri(Uri.base);
    return invitationFromUri(
      currentUri,
      onInviteFragmentDetected: kIsWeb
          ? (Uri scrubbedUri) {
              unawaited(
                SystemNavigator.routeInformationUpdated(
                  uri: scrubbedUri,
                  replace: true,
                ),
              );
            }
          : null,
    );
  }
}

@visibleForTesting
Invitation? invitationFromUri(
  Uri currentUri, {
  void Function(Uri scrubbedUri)? onInviteFragmentDetected,
}) {
  if (!_hasInvitationParameter(currentUri.fragment)) {
    return null;
  }
  onInviteFragmentDetected?.call(_withoutFragment(currentUri));
  try {
    return Invitation.fromQrPayload(currentUri.toString());
  } on FormatException {
    return null;
  }
}

bool _hasInvitationParameter(String fragment) {
  for (final String component in fragment.split('&')) {
    final int separator = component.indexOf('=');
    final String encodedKey = separator < 0
        ? component
        : component.substring(0, separator);
    try {
      if (Uri.decodeQueryComponent(encodedKey) == 'invite') {
        return true;
      }
    } on FormatException {
      if (encodedKey == 'invite') {
        return true;
      }
    }
  }
  return false;
}

Plan _planFromSnapshot(PlanSnapshot snapshot) {
  return Plan(
    id: snapshot.sourcePlanId,
    title: snapshot.title,
    plannedStartTime: snapshot.plannedStartTime,
    defaultCueProfile: snapshot.defaultCueProfile,
    steps: snapshot.steps,
    createdAt: snapshot.capturedAt,
    updatedAt: snapshot.capturedAt,
  );
}

Uri _withoutQueryOrFragment(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );
}

Uri _withoutFragment(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    query: uri.hasQuery ? uri.query : null,
  );
}
