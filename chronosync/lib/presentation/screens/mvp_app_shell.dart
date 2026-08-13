import 'package:chronosync/data/portability/plan_archive_service.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/history_screen.dart';
import 'package:chronosync/presentation/screens/identity_settings_screen.dart';
import 'package:chronosync/presentation/screens/plan_library_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';

typedef PlanLaunchCallback =
    Future<void> Function(BuildContext context, Plan plan);
typedef SessionSummaryCallback =
    Future<void> Function(BuildContext context, LiveSession session);
typedef SessionJoinCallback = Future<void> Function(BuildContext context);

class MvpAppShell extends StatefulWidget {
  const MvpAppShell({
    required this.planRepository,
    required this.historyRepository,
    required this.identityRepository,
    required this.initialIdentity,
    required this.archiveService,
    required this.fileService,
    required this.onLaunchPlan,
    required this.onOpenSession,
    required this.onJoinSession,
    super.key,
  });

  final PlanRepository planRepository;
  final SessionHistoryRepository historyRepository;
  final DeviceIdentityRepository identityRepository;
  final DeviceIdentity initialIdentity;
  final PlanArchiveService archiveService;
  final PortabilityFileService fileService;
  final PlanLaunchCallback onLaunchPlan;
  final SessionSummaryCallback onOpenSession;
  final SessionJoinCallback onJoinSession;

  @override
  State<MvpAppShell> createState() => _MvpAppShellState();
}

class _MvpAppShellState extends State<MvpAppShell> {
  int _selectedIndex = 0;
  late DeviceIdentity _identity;

  @override
  void initState() {
    super.initState();
    _identity = widget.initialIdentity;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> destinations = <Widget>[
      PlanLibraryScreen(
        repository: widget.planRepository,
        archiveService: widget.archiveService,
        fileService: widget.fileService,
        onStartPlan: (Plan plan) => widget.onLaunchPlan(context, plan),
        onJoinSession: () => widget.onJoinSession(context),
      ),
      HistoryScreen(
        repository: widget.historyRepository,
        onOpenSession: (LiveSession session) =>
            widget.onOpenSession(context, session),
      ),
      IdentitySettingsScreen(
        repository: widget.identityRepository,
        initialIdentity: _identity,
        onIdentityChanged: (DeviceIdentity identity) {
          setState(() => _identity = identity);
        },
      ),
    ];

    return ChronoResponsiveBuilder(
      builder:
          (
            BuildContext context,
            ChronoWindowClass windowClass,
            BoxConstraints constraints,
          ) {
            if (windowClass == ChronoWindowClass.expanded) {
              return Scaffold(
                body: Row(
                  children: <Widget>[
                    SafeArea(
                      child: NavigationRail(
                        selectedIndex: _selectedIndex,
                        extended: constraints.maxWidth >= 1240,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: ChronoSpacing.sm,
                          ),
                          child: _BrandMark(
                            showLabel: constraints.maxWidth >= 1240,
                          ),
                        ),
                        destinations: const <NavigationRailDestination>[
                          NavigationRailDestination(
                            icon: Icon(Icons.view_timeline_outlined),
                            selectedIcon: Icon(Icons.view_timeline_rounded),
                            label: Text('Sequences'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.history_outlined),
                            selectedIcon: Icon(Icons.history_rounded),
                            label: Text('History'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings_rounded),
                            label: Text('Settings'),
                          ),
                        ],
                        onDestinationSelected: _select,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: destinations,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Scaffold(
              body: SafeArea(
                bottom: false,
                child: IndexedStack(
                  index: _selectedIndex,
                  children: destinations,
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                destinations: const <NavigationDestination>[
                  NavigationDestination(
                    icon: Icon(Icons.view_timeline_outlined),
                    selectedIcon: Icon(Icons.view_timeline_rounded),
                    label: 'Sequences',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(Icons.history_rounded),
                    label: 'History',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: 'Settings',
                  ),
                ],
              ),
            );
          },
    );
  }

  void _select(int index) {
    setState(() => _selectedIndex = index);
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.showLabel});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.chronoColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.timer_outlined,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        if (showLabel) ...<Widget>[
          const SizedBox(width: ChronoSpacing.xs),
          Text('ChronoSync', style: Theme.of(context).textTheme.titleLarge),
        ],
      ],
    );
  }
}
