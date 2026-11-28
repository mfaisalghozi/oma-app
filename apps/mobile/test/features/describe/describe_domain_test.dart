import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/describe/data/criterion_label.dart';
import 'package:oma_app/features/describe/domain/entities/describe_criteria.dart';
import 'package:oma_app/features/describe/domain/entities/describe_result.dart';
import 'package:oma_app/features/describe/domain/entities/describe_search.dart';

import '../../helpers/deck_fakes.dart';

void main() {
  group('CriterionLabel', () {
    test('height, age and distance read the way the board does', () {
      expect(
        CriterionLabel.of(
          const Criterion(field: 'height_cm', operator: 'gte', number: 180),
        ),
        '180 cm+',
      );
      expect(
        CriterionLabel.of(
          const Criterion(field: 'age', operator: 'lte', number: 30),
        ),
        'Up to 30',
      );
      expect(
        CriterionLabel.of(
          const Criterion(field: 'distance_km', operator: 'lte', number: 10),
        ),
        'Within 10 km',
      );
    });

    test('catalog fields use their text', () {
      expect(
        CriterionLabel.of(const Criterion(field: 'gender', text: 'Man')),
        'Man',
      );
      expect(
        CriterionLabel.of(const Criterion(field: 'hobby', text: 'Hiking')),
        'Hiking',
      );
    });

    test('bio terms read as Mentions', () {
      expect(
        CriterionLabel.of(const Criterion(field: 'bio', text: 'coffee')),
        'Mentions coffee',
      );
    });

    test('a close row explains the deviation in the field unit', () {
      DescribeResultRow row(int deviation, String field) => DescribeResultRow(
        candidate: deckCard(),
        ordinal: 1,
        profileUpdated: false,
        tier: 'close',
        violations: [
          DescribeViolation(
            criterion: Criterion(field: field, operator: 'gte', number: 180),
            deviation: deviation,
          ),
        ],
      );

      expect(
        CriterionLabel.closeReason(row(2, 'height_cm')),
        '2 cm under your minimum',
      );
      expect(
        CriterionLabel.closeReason(row(1, 'age')),
        '1 year outside your range',
      );
      expect(
        CriterionLabel.closeReason(row(3, 'distance_km')),
        '3 km further than you asked',
      );
    });
  });

  group('criteria and search parsing', () {
    test('reads the BE shape and the mock shape', () {
      final be = DescribeCriteria.fromJson({
        'original_query': 'Male, min 180cm',
        'must': [
          {'field': 'gender', 'operator': 'eq', 'number': null, 'text': 'man'},
          {'field': 'height_cm', 'operator': 'gte', 'number': 180, 'text': ''},
        ],
        'nice': [
          {'field': 'hobby', 'operator': 'contains', 'text': 'Hiking'},
        ],
        'not_searchable': [
          {'text': 'brown hair', 'reason': 'unsupported_field'},
        ],
      });
      expect(be.must, hasLength(2));
      expect(be.must[1].number, 180);
      expect(be.nice.single.text, 'Hiking');
      expect(be.notSearchable.single.text, 'brown hair');

      final mock = DescribeCriteria.fromJson({
        'original_query': 'x',
        'must': [
          {'field': 'height_cm', 'op': '>=', 'value': 180},
        ],
        'nice': [
          {'field': 'hobbies', 'term': 'hiking'},
        ],
      });
      expect(mock.must.single.number, 180);
      expect(mock.nice.single.text, 'hiking');
    });

    test('a search walks statuses and reports terminal states', () {
      final queued = DescribeSearch.fromJson({
        'search_id': 's1',
        'status': 'queued',
        'criteria': null,
        'error_code': null,
        'poll_after_seconds': 2,
      });
      expect(queued.status, DescribeStatus.queued);
      expect(queued.status.isTerminal, isFalse);
      expect(queued.criteria, isNull);

      final failed = DescribeSearch.fromJson({
        'search_id': 's1',
        'status': 'failed',
        'error_code': 'SEARCH_FAILED',
      });
      expect(failed.failed, isTrue);
      expect(failed.status.isTerminal, isTrue);
      expect(failed.errorCode, 'SEARCH_FAILED');
    });
  });
}
