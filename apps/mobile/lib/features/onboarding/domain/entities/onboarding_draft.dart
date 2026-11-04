import 'package:meta/meta.dart';

import 'onboarding_step.dart';

/// Every answer from M06 to M11, kept on the phone until the single
/// `POST /v1/me/onboarding` (the backend takes no per-step saves).
///
/// Stored encrypted (Keychain / Keystore) by [OnboardingDraftStore]. Holds
/// sensitive data under UU PDP, so [toString] never prints field values and
/// nothing here goes to logs or Crashlytics.
@immutable
class OnboardingDraft {
  const OnboardingDraft({
    required this.userId,
    this.fullName,
    this.birthdate,
    this.genderId,
    this.pronounId,
    this.showMeOptionId,
    this.bio,
    this.lookingForIds = const [],
    this.heightCm,
    this.weightKg,
    this.universityId,
    this.universityName,
    this.ambition,
    this.religionId,
    this.personalityTypeId,
    this.hobbyIds = const [],
    this.photos = const [],
    this.location,
    this.notificationsDecided = false,
    this.submitKey,
  });

  factory OnboardingDraft.fromJson(Map<String, Object?> j) => OnboardingDraft(
    userId: j['user_id']! as String,
    fullName: j['full_name'] as String?,
    birthdate: _date(j['birthdate']),
    genderId: j['gender_id'] as String?,
    pronounId: j['pronoun_id'] as String?,
    showMeOptionId: j['show_me_option_id'] as String?,
    bio: j['bio'] as String?,
    lookingForIds: _strings(j['looking_for_ids']),
    heightCm: (j['height_cm'] as num?)?.toInt(),
    weightKg: (j['weight_kg'] as num?)?.toInt(),
    universityId: j['university_id'] as String?,
    universityName: j['university_name'] as String?,
    ambition: j['ambition'] as String?,
    religionId: j['religion_id'] as String?,
    personalityTypeId: j['personality_type_id'] as String?,
    hobbyIds: _strings(j['hobby_ids']),
    photos: [
      for (final p in (j['photos'] as List?) ?? const [])
        if (p is Map) DraftPhoto.fromJson(p.cast<String, Object?>()),
    ],
    location: j['location'] is Map
        ? DraftLocation.fromJson((j['location']! as Map).cast())
        : null,
    notificationsDecided: j['notifications_decided'] == true,
    submitKey: j['submit_key'] as String?,
  );

  /// Owner. A draft left by another account on this phone is discarded.
  final String userId;

  // M06 The basics
  final String? fullName;
  final DateTime? birthdate;
  final String? genderId;
  final String? pronounId;
  final String? showMeOptionId;

  // M07 About you
  final String? bio;
  final List<String> lookingForIds;
  final int? heightCm;
  final int? weightKg;
  final String? universityId;

  /// Shown on M07 after a resume without re-querying the university list.
  final String? universityName;

  // M08 Personality and hobbies
  final String? ambition;
  final String? religionId;
  final String? personalityTypeId;
  final List<String> hobbyIds;

  // M09 Photos, in display order (first is the main photo).
  final List<DraftPhoto> photos;

  // M10 Location, rounded on the device before it is stored.
  final DraftLocation? location;

  // M11 Allowed or "Maybe later": either way the step is done.
  final bool notificationsDecided;

  /// `Idempotency-Key` for the final submit. Created once and reused by
  /// every retry so M11c's Try again never creates a second profile.
  final String? submitKey;

  bool get basicsDone =>
      _len(fullName, 2, 100) &&
      birthdate != null &&
      genderId != null &&
      showMeOptionId != null;

  bool get aboutDone =>
      _len(bio, 1, 255) &&
      lookingForIds.isNotEmpty &&
      _inRange(heightCm, 100, 250) &&
      _inRange(weightKg, 25, 300);

  bool get personalityDone => hobbyIds.isNotEmpty;

  bool get photosDone => photos.any((p) => p.photoId != null);

  bool get locationDone => location != null;

  /// First step the user still has to finish; [OnboardingStep.setup] once
  /// everything is answered.
  OnboardingStep get firstUnfinished {
    if (!basicsDone) return OnboardingStep.basics;
    if (!aboutDone) return OnboardingStep.about;
    if (!personalityDone) return OnboardingStep.personality;
    if (!photosDone) return OnboardingStep.photos;
    if (!locationDone) return OnboardingStep.location;
    if (!notificationsDecided) return OnboardingStep.notifications;
    return OnboardingStep.setup;
  }

  /// Copies with changed fields. Pass a [Nullable] to clear an optional one.
  OnboardingDraft copyWith({
    Nullable<String>? fullName,
    Nullable<DateTime>? birthdate,
    Nullable<String>? genderId,
    Nullable<String>? pronounId,
    Nullable<String>? showMeOptionId,
    Nullable<String>? bio,
    List<String>? lookingForIds,
    Nullable<int>? heightCm,
    Nullable<int>? weightKg,
    Nullable<String>? universityId,
    Nullable<String>? universityName,
    Nullable<String>? ambition,
    Nullable<String>? religionId,
    Nullable<String>? personalityTypeId,
    List<String>? hobbyIds,
    List<DraftPhoto>? photos,
    Nullable<DraftLocation>? location,
    bool? notificationsDecided,
    Nullable<String>? submitKey,
  }) => OnboardingDraft(
    userId: userId,
    fullName: _pick(fullName, this.fullName),
    birthdate: _pick(birthdate, this.birthdate),
    genderId: _pick(genderId, this.genderId),
    pronounId: _pick(pronounId, this.pronounId),
    showMeOptionId: _pick(showMeOptionId, this.showMeOptionId),
    bio: _pick(bio, this.bio),
    lookingForIds: lookingForIds ?? this.lookingForIds,
    heightCm: _pick(heightCm, this.heightCm),
    weightKg: _pick(weightKg, this.weightKg),
    universityId: _pick(universityId, this.universityId),
    universityName: _pick(universityName, this.universityName),
    ambition: _pick(ambition, this.ambition),
    religionId: _pick(religionId, this.religionId),
    personalityTypeId: _pick(personalityTypeId, this.personalityTypeId),
    hobbyIds: hobbyIds ?? this.hobbyIds,
    photos: photos ?? this.photos,
    location: _pick(location, this.location),
    notificationsDecided: notificationsDecided ?? this.notificationsDecided,
    submitKey: _pick(submitKey, this.submitKey),
  );

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'full_name': fullName,
    'birthdate': birthdate == null ? null : _dateString(birthdate!),
    'gender_id': genderId,
    'pronoun_id': pronounId,
    'show_me_option_id': showMeOptionId,
    'bio': bio,
    'looking_for_ids': lookingForIds,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'university_id': universityId,
    'university_name': universityName,
    'ambition': ambition,
    'religion_id': religionId,
    'personality_type_id': personalityTypeId,
    'hobby_ids': hobbyIds,
    'photos': [for (final p in photos) p.toJson()],
    'location': location?.toJson(),
    'notifications_decided': notificationsDecided,
    'submit_key': submitKey,
  };

  /// Never prints answers (UU PDP: no profile data in logs).
  @override
  String toString() => 'OnboardingDraft(next: ${firstUnfinished.name})';

  static T? _pick<T>(Nullable<T>? next, T? current) =>
      next == null ? current : next.value;

  static bool _len(String? s, int min, int max) {
    final n = s?.trim().length ?? 0;
    return n >= min && n <= max;
  }

  static bool _inRange(int? v, int min, int max) =>
      v != null && v >= min && v <= max;

  static List<String> _strings(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// `YYYY-MM-DD`, the format `POST /v1/me/onboarding` expects.
String _dateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String birthdateWire(DateTime d) => _dateString(d);

/// Wraps a value for [OnboardingDraft.copyWith] so `null` can mean "clear".
@immutable
class Nullable<T> {
  const Nullable(this.value);

  final T? value;
}

enum DraftPhotoStatus {
  /// Picked and passed the on-device scan; not uploaded yet.
  pending,
  uploading,
  uploaded,
  failed,
}

/// One M09 tile. [photoId] is the slot reserved with
/// `POST /v1/photos/upload-urls`; a retry reuses it so no duplicate is made.
@immutable
class DraftPhoto {
  const DraftPhoto({
    required this.localPath,
    this.photoId,
    this.status = DraftPhotoStatus.pending,
  });

  factory DraftPhoto.fromJson(Map<String, Object?> j) => DraftPhoto(
    localPath: j['local_path'] as String? ?? '',
    photoId: j['photo_id'] as String?,
    status:
        DraftPhotoStatus.values.asNameMap()[j['status']] ??
        DraftPhotoStatus.pending,
  );

  /// Compressed copy in the app's temp folder, deleted after upload.
  final String localPath;
  final String? photoId;
  final DraftPhotoStatus status;

  bool get isUploaded => status == DraftPhotoStatus.uploaded;

  DraftPhoto copyWith({
    String? localPath,
    Nullable<String>? photoId,
    DraftPhotoStatus? status,
  }) => DraftPhoto(
    localPath: localPath ?? this.localPath,
    photoId: photoId == null ? this.photoId : photoId.value,
    status: status ?? this.status,
  );

  Map<String, Object?> toJson() => {
    'local_path': localPath,
    'photo_id': photoId,
    'status': status.name,
  };
}

enum LocationSource { gps, city }

/// Coordinates already rounded on the device (M10). For a picked city these
/// are the city centre.
@immutable
class DraftLocation {
  const DraftLocation({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.cityName,
  });

  factory DraftLocation.fromJson(Map<String, Object?> j) => DraftLocation(
    latitude: (j['latitude']! as num).toDouble(),
    longitude: (j['longitude']! as num).toDouble(),
    source: j['source'] == 'city' ? LocationSource.city : LocationSource.gps,
    cityName: j['city_name'] as String?,
  );

  final double latitude;
  final double longitude;
  final LocationSource source;
  final String? cityName;

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'source': source.name,
    'city_name': cityName,
  };
}
