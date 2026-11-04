/// The six counted profile steps (M06 to M11) plus the M11b/M11c setup screen.
/// The path segment is what goes in `/onboarding/:step`.
enum OnboardingStep {
  basics('basics', 1), // M06
  about('about', 2), // M07
  personality('personality', 3), // M08
  photos('photos', 4), // M09
  location('location', 5), // M10
  notifications('notifications', 6), // M11
  setup('setup', null); // M11b / M11c

  const OnboardingStep(this.path, this.number);

  final String path;

  /// "Step n of 6"; null for the setup screen.
  final int? number;

  static const counted = 6;

  static OnboardingStep? fromPath(String? path) {
    for (final s in values) {
      if (s.path == path) return s;
    }
    return null;
  }

  OnboardingStep? get next {
    final i = index + 1;
    return i < values.length ? values[i] : null;
  }
}
