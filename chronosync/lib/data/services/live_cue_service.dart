import 'dart:async';

import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

enum LiveCueKind { approaching, due, overdue }

final class LiveCue {
  const LiveCue({
    required this.kind,
    required this.stepIndex,
    required this.stepTitle,
  });

  final LiveCueKind kind;
  final int stepIndex;
  final String stepTitle;
}

/// Cue boundary consumed by live-session orchestration.
///
/// Keeping this contract narrow makes controller cleanup deterministic when a
/// platform cue implementation fails during startup or recovery.
abstract interface class LiveCueDelivery {
  Stream<LiveCue> get cues;

  Future<void> unlockAudio();

  Future<void> evaluate(LiveSession session, DateTime now);
}

/// Platform boundary for haptic cue delivery.
abstract interface class LiveCueHaptics {
  Future<void> deliver(LiveCueKind kind);
}

final class PlatformLiveCueHaptics implements LiveCueHaptics {
  const PlatformLiveCueHaptics();

  @override
  Future<void> deliver(LiveCueKind kind) async {
    if (!_hapticsSupported) {
      return;
    }
    switch (kind) {
      case LiveCueKind.approaching:
        await HapticFeedback.lightImpact();
      case LiveCueKind.due:
        await HapticFeedback.mediumImpact();
      case LiveCueKind.overdue:
        await HapticFeedback.heavyImpact();
    }
  }
}

/// Emits each foreground cue once per step and fans it out to the enabled
/// visual, audio, and haptic channels.
final class LiveCueService implements LiveCueDelivery {
  LiveCueService({AudioPlayer? audioPlayer, LiveCueHaptics? haptics})
    : _audioPlayer = audioPlayer ?? AudioPlayer(),
      _haptics = haptics ?? const PlatformLiveCueHaptics();

  final AudioPlayer _audioPlayer;
  final LiveCueHaptics _haptics;
  final StreamController<LiveCue> _cueController =
      StreamController<LiveCue>.broadcast();
  final Set<String> _delivered = <String>{};

  bool _audioReady = false;

  @override
  Stream<LiveCue> get cues => _cueController.stream;

  /// Call from the Start or Join gesture so browsers may enable audio.
  @override
  Future<void> unlockAudio() async {
    if (_audioReady) {
      return;
    }
    try {
      await _audioPlayer.setAsset('assets/audio/auto_progress_beep.mp3');
      _audioReady = true;
    } on Object {
      _audioReady = false;
    }
  }

  @override
  Future<void> evaluate(LiveSession session, DateTime now) async {
    if (session.status != LiveSessionStatus.running) {
      return;
    }
    final Step step = session.currentStep;
    final CueProfile cue =
        step.cueOverride ?? session.planSnapshot.defaultCueProfile;
    final Duration remaining = session.remainingAt(now);

    if (remaining > Duration.zero &&
        remaining <= Duration(seconds: cue.approachingSeconds) &&
        cue.includesApproachingCueFor(
          step.duration,
          isStepOverride: step.cueOverride != null,
        )) {
      await _deliver(session, cue, LiveCueKind.approaching);
    }
    if (remaining <= Duration.zero) {
      await _deliver(session, cue, LiveCueKind.due);
    }
    if (remaining <= Duration(seconds: -cue.overdueSeconds)) {
      await _deliver(session, cue, LiveCueKind.overdue);
    }
  }

  Future<void> _deliver(
    LiveSession session,
    CueProfile profile,
    LiveCueKind kind,
  ) async {
    final String key =
        '${session.id}:${session.currentStepIndex}:'
        '${session.currentStepStartedAt?.microsecondsSinceEpoch}:${kind.name}';
    if (!_delivered.add(key)) {
      return;
    }
    final LiveCue cue = LiveCue(
      kind: kind,
      stepIndex: session.currentStepIndex,
      stepTitle: session.currentStep.title,
    );
    if (profile.visualEnabled && !_cueController.isClosed) {
      _cueController.add(cue);
    }
    if (profile.soundEnabled && _audioReady) {
      try {
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();
      } on Object {
        // A cue remains useful visually even if audio is unavailable.
      }
    }
    if (profile.hapticEnabled) {
      try {
        await _haptics.deliver(kind);
      } on Object {
        // Visual and audio cues remain useful if haptics are unavailable.
      }
    }
  }

  Future<void> dispose() async {
    await _cueController.close();
    await _audioPlayer.dispose();
  }
}

bool get _hapticsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);
