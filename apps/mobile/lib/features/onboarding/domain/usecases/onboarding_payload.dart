import '../entities/onboarding_draft.dart';
import '../entities/onboarding_step.dart';

/// Empty optional fields are omitted; only uploaded photos are sent, 1-based.
Map<String, Object?> onboardingPayload(OnboardingDraft d) {
  String? text(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
  final photos = d.photos.where((p) => p.isUploaded).toList();
  return {
    'profile': {
      'full_name': text(d.fullName),
      if (d.birthdate != null) 'birthdate': birthdateWire(d.birthdate!),
      'gender_id': d.genderId,
      'pronoun_id': ?d.pronounId,
      'show_me_option_id': d.showMeOptionId,
      'bio': text(d.bio),
      'height_cm': d.heightCm,
      'weight_kg': d.weightKg,
      'university_id': ?d.universityId,
      'ambition': ?text(d.ambition),
      'religion_id': ?d.religionId,
      'personality_type_id': ?d.personalityTypeId,
    },
    'looking_for_ids': d.lookingForIds,
    'hobby_ids': d.hobbyIds,
    'photos': [
      for (var i = 0; i < photos.length; i++)
        {'photo_id': photos[i].photoId, 'position': i + 1},
    ],
    if (d.location != null)
      'location': {
        'latitude': d.location!.latitude,
        'longitude': d.location!.longitude,
      },
  };
}

/// The step that owns a field named in a 422 `{field, reason}` detail.
/// Accepts `profile.bio` and `bio` alike; unknown fields go to M06.
OnboardingStep stepForField(String field) {
  final name = field.split('.').last.replaceAll(RegExp(r'\[\d+\]'), '');
  return switch (name) {
    'bio' ||
    'looking_for_ids' ||
    'height_cm' ||
    'weight_kg' ||
    'university_id' => OnboardingStep.about,
    'ambition' ||
    'religion_id' ||
    'personality_type_id' ||
    'hobby_ids' => OnboardingStep.personality,
    'photos' || 'photo_id' || 'position' => OnboardingStep.photos,
    'location' || 'latitude' || 'longitude' => OnboardingStep.location,
    _ => OnboardingStep.basics,
  };
}
