-- Delete only the deterministic seed identities introduced by this migration.
DELETE FROM hobby_categories WHERE id IN (
'659222d0-8f3d-551b-95f1-dab9ed7bf7d4',
'ab4b40dc-1bdb-5098-82da-ef0607f5d0bd',
'9c97ded2-ea2b-59c4-aae8-ef1f2bc99d8a'
);
