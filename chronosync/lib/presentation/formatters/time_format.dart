String formatClock(Duration duration, {bool showSign = false}) {
  final bool negative = duration.isNegative;
  final int seconds = duration.inSeconds.abs();
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  final int remainder = seconds % 60;
  final String value = hours > 0
      ? '${hours.toString().padLeft(2, '0')}:'
            '${minutes.toString().padLeft(2, '0')}:'
            '${remainder.toString().padLeft(2, '0')}'
      : '${minutes.toString().padLeft(2, '0')}:'
            '${remainder.toString().padLeft(2, '0')}';
  if (negative) {
    return '-$value';
  }
  if (showSign && duration > Duration.zero) {
    return '+$value';
  }
  return value;
}

String formatFriendlyDuration(Duration duration) {
  final int totalMinutes = duration.inMinutes;
  final int seconds = duration.inSeconds.remainder(60);
  if (totalMinutes >= 60) {
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes.remainder(60);
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
  if (totalMinutes > 0) {
    return seconds == 0 ? '${totalMinutes}m' : '${totalMinutes}m ${seconds}s';
  }
  return '${duration.inSeconds}s';
}

String safeFileStem(String title) {
  final String normalized = title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? 'chronosync' : normalized;
}
