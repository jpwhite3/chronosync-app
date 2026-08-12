/// Parses an ISO-8601 timestamp whose source time zone is explicit.
///
/// Requiring `Z` or a numeric UTC offset prevents the same persisted or wire
/// value from being interpreted differently on devices in different zones.
DateTime parseUtcTimestamp(String value, {String fieldName = 'timestamp'}) {
  final bool hasExplicitZone = RegExp(
    r'(?:[zZ]|[+-]\d{2}:?\d{2})$',
  ).hasMatch(value);
  final DateTime? parsed = hasExplicitZone ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    throw FormatException(
      '$fieldName must be a valid ISO-8601 timestamp with an explicit time zone.',
    );
  }
  return parsed.toUtc();
}
