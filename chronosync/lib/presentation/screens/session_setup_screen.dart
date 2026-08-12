import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';

enum SessionLaunchMode { solo, nearby, online }

class SessionSetupScreen extends StatelessWidget {
  const SessionSetupScreen({
    required this.plan,
    required this.nearbyAvailable,
    required this.onlineAvailable,
    required this.onLaunch,
    this.isLaunching = false,
    this.errorMessage,
    super.key,
  });

  final Plan plan;
  final bool nearbyAvailable;
  final bool onlineAvailable;
  final ValueChanged<SessionLaunchMode> onLaunch;
  final bool isLaunching;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start live session')),
      body: SingleChildScrollView(
        padding: ChronoBreakpoints.pagePaddingFor(
          MediaQuery.sizeOf(context).width,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  plan.title,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: ChronoSpacing.xs),
                Text(
                  '${plan.steps.length} steps · '
                  '${formatFriendlyDuration(plan.totalDuration)}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (plan.plannedStartTime != null) ...<Widget>[
                  const SizedBox(height: ChronoSpacing.xs),
                  const Row(
                    children: <Widget>[
                      Icon(Icons.schedule_rounded, size: 20),
                      SizedBox(width: ChronoSpacing.xs),
                      Expanded(
                        child: Text(
                          'Scheduled start is enabled. The session will begin '
                          'when that time arrives.',
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: ChronoSpacing.lg),
                Text(
                  'How will the team join?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: ChronoSpacing.sm),
                _LaunchOption(
                  title: 'Just me',
                  description:
                      'Run the plan on this device with the complete timer, '
                      'history, cues, and summary.',
                  icon: Icons.person_outline_rounded,
                  badge: 'Fastest',
                  enabled: !isLaunching,
                  onPressed: () => onLaunch(SessionLaunchMode.solo),
                ),
                const SizedBox(height: ChronoSpacing.sm),
                _LaunchOption(
                  title: 'Nearby team',
                  description: nearbyAvailable
                      ? 'Host from this iPhone over the current Wi‑Fi network. '
                            'No Internet connection is required.'
                      : 'Nearby hosting requires the iPhone app. You can still '
                            'join a nearby session from this device.',
                  icon: Icons.wifi_tethering_rounded,
                  badge: 'Offline',
                  enabled: nearbyAvailable && !isLaunching,
                  onPressed: () => onLaunch(SessionLaunchMode.nearby),
                ),
                const SizedBox(height: ChronoSpacing.sm),
                _LaunchOption(
                  title: 'Online team',
                  description: onlineAvailable
                      ? 'Share an expiring encrypted link with teammates on '
                            'any supported browser.'
                      : 'Online rooms aren’t available in this build. You can '
                            'still run solo or join a shared session.',
                  icon: Icons.language_rounded,
                  badge: 'Anywhere',
                  enabled: onlineAvailable && !isLaunching,
                  onPressed: () => onLaunch(SessionLaunchMode.online),
                ),
                if (isLaunching) ...<Widget>[
                  const SizedBox(height: ChronoSpacing.md),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (errorMessage != null) ...<Widget>[
                  const SizedBox(height: ChronoSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchOption extends StatelessWidget {
  const _LaunchOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.badge,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final String description;
  final IconData icon;
  final String badge;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.62,
      child: ChronoCard(
        onTap: enabled ? onPressed : null,
        semanticLabel:
            '$title. $description. ${enabled ? 'Available' : 'Unavailable'}',
        padding: const EdgeInsets.all(ChronoSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.chronoColors.primaryContainer,
                borderRadius: ChronoRadii.controlBorder,
              ),
              child: Icon(icon, color: context.chronoColors.primary),
            ),
            const SizedBox(width: ChronoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: ChronoSpacing.xs,
                    runSpacing: ChronoSpacing.xs,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ChronoStatusPill(
                        status: ChronoStatus.neutral,
                        label: badge,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: ChronoSpacing.xs),
                  Text(description),
                ],
              ),
            ),
            const SizedBox(width: ChronoSpacing.xs),
            Icon(enabled ? Icons.arrow_forward_rounded : Icons.lock_outline),
          ],
        ),
      ),
    );
  }
}
