/// Statistics calculated at series completion
///
/// This is a transient model (not persisted to Hive) that captures
/// aggregate information about a completed series execution.
class SeriesStatistics {
  /// Total number of events in the completed series
  final int eventCount;

  /// Sum of all event durations in seconds
  final int expectedTimeSeconds;

  /// Actual elapsed time including overtime/undertime in seconds
  final int actualTimeSeconds;

  const SeriesStatistics({
    required this.eventCount,
    required this.expectedTimeSeconds,
    required this.actualTimeSeconds,
  });

  /// Difference between actual and expected time (positive = overtime, negative = undertime)
  int get overUnderTimeSeconds => actualTimeSeconds - expectedTimeSeconds;

  /// Whether the series ran overtime (actual > expected)
  bool get isOvertime => overUnderTimeSeconds > 0;

  /// Whether the series ran undertime (actual < expected)
  bool get isUndertime => overUnderTimeSeconds < 0;

  /// Whether the series ran exactly on time (actual == expected)
  bool get isOnTime => overUnderTimeSeconds == 0;

  /// Formatted expected time string (MM:SS or HH:MM:SS)
  String get expectedTimeFormatted => _formatTime(expectedTimeSeconds);

  /// Formatted actual time string (MM:SS or HH:MM:SS)
  String get actualTimeFormatted => _formatTime(actualTimeSeconds);

  /// Formatted over/under time string with sign prefix (+/-/none)
  String get overUnderTimeFormatted {
    final String sign = isOvertime ? '+' : (isUndertime ? '-' : '');
    return '$sign${_formatTime(overUnderTimeSeconds.abs())}';
  }

  /// Format seconds into HH:MM:SS or MM:SS string
  String _formatTime(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
  }

  @override
  String toString() {
    return 'SeriesStatistics('
        'eventCount: $eventCount, '
        'expected: $expectedTimeFormatted, '
        'actual: $actualTimeFormatted, '
        'over/under: $overUnderTimeFormatted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SeriesStatistics &&
        other.eventCount == eventCount &&
        other.expectedTimeSeconds == expectedTimeSeconds &&
        other.actualTimeSeconds == actualTimeSeconds;
  }

  @override
  int get hashCode =>
      eventCount.hashCode ^
      expectedTimeSeconds.hashCode ^
      actualTimeSeconds.hashCode;
}
