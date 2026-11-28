import 'package:meta/meta.dart';

int _int(Object? value) => value is num ? value.toInt() : 0;
String? _str(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

@immutable
class DeckPhoto {
  const DeckPhoto({
    required this.id,
    required this.position,
    required this.readUrl,
  });

  factory DeckPhoto.fromJson(Map<String, Object?> json) => DeckPhoto(
    id: json['id'] as String? ?? '',
    position: _int(json['position']),
    readUrl: json['read_url'] as String? ?? '',
  );

  final String id;
  final int position;
  final String readUrl;
}

@immutable
class DeckOption {
  const DeckOption({required this.id, required this.code, required this.label});

  factory DeckOption.fromJson(Map<String, Object?> json) => DeckOption(
    id: json['id'] as String? ?? '',
    code: json['code'] as String? ?? '',
    label: json['label'] as String? ?? '',
  );

  final String id;
  final String code;
  final String label;
}

@immutable
class DeckUniversity {
  const DeckUniversity({
    required this.id,
    required this.name,
    required this.countryCode,
  });

  factory DeckUniversity.fromJson(Map<String, Object?> json) => DeckUniversity(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    countryCode: json['country_code'] as String? ?? '',
  );

  final String id;
  final String name;
  final String countryCode;
}

/// One person in the deck. The BE sends the same shape in Describe results.
@immutable
class DeckCard {
  const DeckCard({
    required this.id,
    required this.displayName,
    required this.age,
    required this.approxDistanceKm,
    required this.photos,
    this.heightCm,
    this.bio,
    this.ambition,
    this.occupation,
    this.educationDegree,
    this.profileRevision = 0,
    this.hobbies = const [],
    this.lookingFor = const [],
    this.personality,
    this.religion,
    this.university,
  });

  factory DeckCard.fromJson(Map<String, Object?> json) => DeckCard(
    id: json['id'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    age: _int(json['age']),
    heightCm: json['height_cm'] == null ? null : _int(json['height_cm']),
    approxDistanceKm: _int(json['approx_distance_km']),
    bio: _str(json['bio']),
    ambition: _str(json['ambition']),
    occupation: _str(json['occupation']),
    educationDegree: _str(json['education_degree']),
    profileRevision: _int(json['profile_revision']),
    photos: [
      for (final photo in (json['photos'] as List? ?? const []))
        DeckPhoto.fromJson((photo as Map).cast()),
    ]..sort((a, b) => a.position.compareTo(b.position)),
    hobbies: [
      for (final hobby in (json['hobbies'] as List? ?? const []))
        DeckOption.fromJson((hobby as Map).cast()),
    ],
    lookingFor: [
      for (final item in (json['looking_for'] as List? ?? const []))
        DeckOption.fromJson((item as Map).cast()),
    ],
    personality: json['personality'] == null
        ? null
        : DeckOption.fromJson((json['personality'] as Map).cast()),
    religion: json['religion'] == null
        ? null
        : DeckOption.fromJson((json['religion'] as Map).cast()),
    university: json['university'] == null
        ? null
        : DeckUniversity.fromJson((json['university'] as Map).cast()),
  );

  final String id;
  final String displayName;
  final int age;
  final int? heightCm;
  final int approxDistanceKm;
  final String? bio;
  final String? ambition;
  final String? occupation;
  final String? educationDegree;
  final int profileRevision;
  final List<DeckPhoto> photos;
  final List<DeckOption> hobbies;
  final List<DeckOption> lookingFor;
  final DeckOption? personality;
  final DeckOption? religion;
  final DeckUniversity? university;

  /// The board shows hobbies then personality. Section 16: hair is not a field,
  /// so it never appears here.
  List<String> get tags => [
    for (final hobby in hobbies) hobby.label,
    if (personality case final personality?) personality.label,
  ];

  String get distanceLabel => '$approxDistanceKm km away';
}
