# ONB-BE-04 — approved initial catalog

Status: **approved by the user on 2026-11-09 for explicit database seeding**.
The reviewed revision renames the short-term label to `Short-term` and excludes
Confucianism. [initial-review.sql](initial-review.sql) retains its original filename
for traceability and is now the approved, transactional seed script. It is outside
`migrations/`, so API migrations do not apply it.

## Approved values

| Catalog | Approved values |
| --- | --- |
| Pronoun | He/Him, She/Her, They/Them |
| Looking for | Long-term relationship, Short-term, Friendship, Still figuring it out |
| Religion | Islam, Christianity, Catholicism, Hinduism, Buddhism, Agnostic, Atheist, Other, Prefer not to say |
| University | Universitas Indonesia, Institut Teknologi Bandung, Universitas Gadjah Mada (all `ID`) |
| Outdoor hobbies | Hiking, Running, Cycling, Camping, Swimming, Badminton |
| Indoor hobbies | Reading, Cooking, Baking, Movies, Music, Photography |
| Gaming hobbies | Board games, Mobile games, PC games, Console games |

Outdoor, Indoor and Gaming are already backed by PRD M08 and migration 009.
The user approved the remaining values shown above. Labels use English;
university proper names retain their official spelling. The university coverage
is intentionally limited to the approved initial set.

The university list is a small starting set, not a national directory. Name and
country references were checked against the universities' official sites:
[Universitas Indonesia](https://scholar.ui.ac.id/en/organisations/universitas-indonesia/),
[Institut Teknologi Bandung](https://itb.ac.id/), and
[Universitas Gadjah Mada](https://oia.ugm.ac.id/about-ugm/).
Choose target countries, coverage, update owner and source before expanding it.

## Application and maintenance

The user authorized applying this exact reviewed catalog to the API database on
2026-11-09. Seeding is explicit and separate from schema migration. Apply the whole
SQL file in one database session; its BEGIN/COMMIT makes the operation atomic.

The script assigns deterministic UUIDs to additions, uses existing category IDs
by code, and preserves existing labels and inactive flags on natural-key conflicts.
Running it twice does not duplicate rows. It does not remove existing options.
Deactivate retired options rather than deleting values referenced by profiles.
Changing an existing label requires an explicit update; re-running this insert-only
seed will not overwrite it. Later taxonomy additions require a new product review.

HTTP integration tests load the seed twice into an isolated PostgreSQL/PostGIS
schema, then verify searchable options, the reviewed label, the nine religion
options, and hobby category associations through the API.

## Application receipt — 2026-11-09

Applied to the existing OMA Supabase project `hflxevzciognmavdpcnt` using the API's
configured database connection, following the user's explicit seed instruction.
The seed acquired the migration advisory lock and committed in one transaction.
Existing He/Him and category identities were preserved. No schema migrations,
profile records, legal documents or Auth settings were changed.

| Catalog | Before | Verified after commit |
| --- | ---: | ---: |
| Pronoun | 1 | 3 |
| Looking for | 0 | 4 |
| Religion | 0 | 9 |
| Hobby category | 3 | 3 |
| University | 0 | 3 |
| Hobby | 0 | 16 |

The reviewed `Short-term` label and category associations were checked before
commit; row counts were verified again from a new read-only connection afterward.
Full race-enabled PostgreSQL/PostGIS integration and adapter tests passed.
Separate Standards and Spec reviews of the approved revision found no actionable
issues. Tests used only the disposable database; no production users were created.
