import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Today's date on the phone; overridden in tests.
final todayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Age in whole years on [today].
int ageOn(DateTime birthdate, DateTime today) {
  var age = today.year - birthdate.year;
  if (today.month < birthdate.month ||
      (today.month == birthdate.month && today.day < birthdate.day)) {
    age--;
  }
  return age;
}

const minimumAge = 18;
