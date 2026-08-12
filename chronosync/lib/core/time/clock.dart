/// Supplies the current time to timer and session state.
///
/// Keeping time behind this small interface makes timestamp-based state
/// deterministic in tests and lets nearby participants apply a host clock
/// offset without changing their timer logic.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
