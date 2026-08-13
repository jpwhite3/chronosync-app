import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef SessionSelectedCallback = Future<void> Function(LiveSession session);

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    required this.repository,
    required this.onOpenSession,
    super.key,
  });

  final SessionHistoryRepository repository;
  final SessionSelectedCallback onOpenSession;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveSession>>(
      stream: repository.watchSessions(),
      builder:
          (BuildContext context, AsyncSnapshot<List<LiveSession>> snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(ChronoSpacing.lg),
                  child: Text(
                    'Session history could not be loaded.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<LiveSession> sessions = snapshot.data!;
            return CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(child: _HistoryHeader(sessions: sessions)),
                if (sessions.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyHistory(),
                  )
                else
                  SliverPadding(
                    padding: ChronoBreakpoints.pagePaddingFor(
                      MediaQuery.sizeOf(context).width,
                    ),
                    sliver: SliverList.separated(
                      itemCount: sessions.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: ChronoSpacing.xs),
                      itemBuilder: (BuildContext context, int index) {
                        final LiveSession session = sessions[index];
                        return _HistoryCard(
                          session: session,
                          onPressed: () => onOpenSession(session),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.sessions});

  final List<LiveSession> sessions;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pagePadding = ChronoBreakpoints.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );
    return Padding(
      padding: pagePadding.copyWith(bottom: ChronoSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('History', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: ChronoSpacing.xxs),
          Text(
            sessions.isEmpty
                ? 'Completed and ended sessions will appear here.'
                : '${sessions.length} recent '
                      '${sessions.length == 1 ? 'session' : 'sessions'}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(ChronoSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.history_rounded,
                size: 56,
                color: context.chronoColors.textSecondary,
              ),
              const SizedBox(height: ChronoSpacing.sm),
              Text(
                'No sessions yet',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: ChronoSpacing.xs),
              const Text(
                'Start a sequence to capture its actual timing, actions, and '
                'timing drift.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.session, required this.onPressed});

  final LiveSession session;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final DateTime timestamp =
        session.startedAt ?? session.planSnapshot.capturedAt;
    final String semanticLabel = session.hasCompleteActivityHistory
        ? 'Open ${session.planSnapshot.title} session summary.'
        : 'Open ${session.planSnapshot.title} session summary. '
              'Incomplete activity history.';

    return ChronoCard(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.chronoColors.surfaceMuted,
                  borderRadius: ChronoRadii.controlBorder,
                ),
                child: const Icon(Icons.timeline_rounded),
              ),
              const SizedBox(width: ChronoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      session.planSnapshot.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: ChronoSpacing.xxs),
                    Text(
                      '${DateFormat.yMMMd().add_jm().format(timestamp.toLocal())}'
                      ' • ${session.planSnapshot.steps.length} '
                      '${session.planSnapshot.steps.length == 1 ? 'interval' : 'intervals'}'
                      ' • ${formatFriendlyDuration(session.totalElapsedAt(DateTime.now()))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ChronoSpacing.xs),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: ChronoSpacing.xs),
          Wrap(
            spacing: ChronoSpacing.xs,
            runSpacing: ChronoSpacing.xs,
            children: <Widget>[
              const ChronoStatusPill(
                label: 'Ended',
                status: ChronoStatus.neutral,
              ),
              if (!session.hasCompleteActivityHistory)
                const ChronoStatusPill(
                  label: 'Incomplete activity history',
                  semanticLabel:
                      'Incomplete activity history. Earlier activity may '
                      'be missing on this device.',
                  status: ChronoStatus.approaching,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
