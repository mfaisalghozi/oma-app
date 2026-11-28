import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/discover/domain/entities/deck_card.dart';
import 'package:oma_app/features/discover/domain/entities/deck_page.dart';

void main() {
  test('parses a DiscoveryCard and puts hobbies before personality', () {
    final card = DeckCard.fromJson({
      'id': 'c1',
      'display_name': 'Dimas',
      'age': 28,
      'height_cm': 178,
      'approx_distance_km': 4,
      'bio': 'Trails on weekends.',
      'ambition': 'Run the Jakarta Marathon under 4 hours',
      'occupation': null,
      'education_degree': null,
      'profile_revision': 12,
      'photos': [
        {'id': 'p1', 'position': 1, 'read_url': 'https://x/1.jpg'},
        {'id': 'p0', 'position': 0, 'read_url': 'https://x/0.jpg'},
      ],
      'hobbies': [
        {'id': 'h1', 'code': 'running', 'label': 'Running'},
      ],
      'looking_for': [
        {'id': 'l1', 'code': 'serious', 'label': 'Something serious'},
      ],
      'personality': {'id': 'pp', 'code': 'enfp', 'label': 'ENFP'},
      'religion': {'id': 'r1', 'code': 'islam', 'label': 'Islam'},
      'university': {
        'id': 'u1',
        'name': 'Universitas Indonesia',
        'country_code': 'ID',
      },
    });

    expect(card.displayName, 'Dimas');
    expect(card.age, 28);
    expect(card.heightCm, 178);
    expect(card.distanceLabel, '4 km away');
    expect(card.tags, ['Running', 'ENFP']);
    expect(card.photos.first.position, 0);
    expect(card.photos.first.id, 'p0');
    expect(card.university?.name, 'Universitas Indonesia');
    expect(card.lookingFor.single.label, 'Something serious');
  });

  test('tolerates a card with no photos, ambition or personality', () {
    final card = DeckCard.fromJson({
      'id': 'c2',
      'display_name': 'Ayu',
      'age': 24,
      'approx_distance_km': 9,
      'photos': const [],
      'hobbies': const [],
      'looking_for': const [],
    });

    expect(card.photos, isEmpty);
    expect(card.ambition, isNull);
    expect(card.tags, isEmpty);
    expect(card.distanceLabel, '9 km away');
  });

  test('parses a deck page with an exhausted end reason', () {
    final page = DeckPage.fromJson({
      'context_id': 'ctx',
      'cards': const [],
      'next_cursor': null,
      'deck_expires_at': '2026-11-27T18:00:00Z',
      'end_reason': 'candidate_pool_exhausted',
    });

    expect(page.cards, isEmpty);
    expect(page.nextCursor, isNull);
    expect(page.isExhausted, isTrue);
    expect(page.deckExpiresAt, DateTime.utc(2026, 11, 27, 18));
  });
}
