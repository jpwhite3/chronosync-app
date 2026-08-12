import 'package:flutter/widgets.dart';

/// Shared spacing and shape tokens for ChronoSync.
abstract final class ChronoSpacing {
  static const double hairline = 1;
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 40;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// Exceeds the 44-point accessibility minimum on every supported platform.
  static const double minimumTouchTarget = 48;
}

/// Shared corner radii for controls and surfaces.
abstract final class ChronoRadii {
  static const double control = 14;
  static const double surface = 16;
  static const double feature = 24;
  static const double pill = 999;

  static const BorderRadius controlBorder = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius surfaceBorder = BorderRadius.all(
    Radius.circular(surface),
  );
  static const BorderRadius featureBorder = BorderRadius.all(
    Radius.circular(feature),
  );
}
