import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LiveTimerScreen extends StatelessWidget {
  const LiveTimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Timer')),
      body: BlocBuilder<LiveTimerBloc, LiveTimerState>(
        builder: (context, state) {
          if (state is LiveTimerInitial) {
            return const Center(child: Text('Initializing...'));
          }

          if (state is LiveTimerRunning) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    state.currentEvent.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  // Countdown Timer Section
                  Text(
                    'Time Remaining',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatCountdown(state),
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: state.isOvertime ? Colors.red : null,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Elapsed Timer Section
                  Text(
                    'Time Elapsed',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(state.elapsedSeconds),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () {
                      context.read<LiveTimerBloc>().add(NextEvent());
                    },
                    child: const Text('NEXT'),
                  ),
                ],
              ),
            );
          }

          if (state is LiveTimerCompleted) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'All events completed!',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Back to Series'),
                  ),
                ],
              ),
            );
          }

          return const Center(child: Text('Unknown state'));
        },
      ),
    );
  }

  String _formatDuration(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }

  /// Formats countdown timer with negative sign when in overtime
  String _formatCountdown(LiveTimerRunning state) {
    if (state.isOvertime) {
      // Show negative time using overtimeSeconds
      return '-${_formatDuration(state.overtimeSeconds)}';
    }
    // Show remaining time normally
    return _formatDuration(state.remainingSeconds);
  }
}
