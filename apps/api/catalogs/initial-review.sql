-- Approved initial catalog, reviewed and authorized for seeding on 2026-11-09.
-- Explicit seed script; not applied by schema migrations.
-- Existing rows, labels and inactive flags are preserved on conflict.
BEGIN;
INSERT INTO pronoun_options(id,code,label) VALUES
('e96044af-ed8d-5d2a-acf2-6eb13232b97e','he_him','He/Him'),
('b13a2d50-562d-5afc-8071-d6efc7b824cd','she_her','She/Her'),
('42f0e58b-6064-55b7-bf30-f00d687f2d32','they_them','They/Them')
ON CONFLICT(code) DO NOTHING;
INSERT INTO looking_for_options(id,code,label) VALUES
('3bed56b3-c87f-5fc3-8cc0-6a1c0498c134','long_term_relationship','Long-term relationship'),
('d6727001-96fb-5ce8-994e-72626d195333','short_term_dating','Short-term'),
('6dae1158-6367-557a-a85a-500b668f6ca8','friendship','Friendship'),
('7d3cdf76-9ebd-54a2-8802-dec4524c8c72','still_figuring_it_out','Still figuring it out')
ON CONFLICT(code) DO NOTHING;
INSERT INTO religions(id,code,label) VALUES
('e2dfe1f5-a81a-5c16-b8f0-ccfa77158a1d','islam','Islam'),
('1bc0c90f-5ae8-5d81-a7e1-7e08c234d3af','christianity','Christianity'),
('20156ab8-5a46-52a1-84fd-a8205d7ad92a','catholicism','Catholicism'),
('85290dc2-e39b-5d77-9061-aacf0b928f74','hinduism','Hinduism'),
('cd5b4d55-322a-5932-af53-32d196beaa6f','buddhism','Buddhism'),
('ee2ca509-e854-55c4-8487-9665d5106318','agnostic','Agnostic'),
('2fc99da8-e463-5b40-9f1d-239652f1be71','atheist','Atheist'),
('3327b9c2-763c-56ab-87b4-b445da1910ff','other','Other'),
('0e2fe1cc-7f9a-54fa-ab59-f97d6e37437a','prefer_not_to_say','Prefer not to say')
ON CONFLICT(code) DO NOTHING;
INSERT INTO hobby_categories(id,code,label) VALUES
('659222d0-8f3d-551b-95f1-dab9ed7bf7d4','outdoor','Outdoor'),
('ab4b40dc-1bdb-5098-82da-ef0607f5d0bd','indoor','Indoor'),
('9c97ded2-ea2b-59c4-aae8-ef1f2bc99d8a','gaming','Gaming')
ON CONFLICT(code) DO NOTHING;
INSERT INTO universities(id,name,country_code) VALUES
('8033d2e8-2697-5841-9108-dc954450ea35','Universitas Indonesia','ID'),
('cdb11270-d663-5f08-8f1e-af087a32266a','Institut Teknologi Bandung','ID'),
('ab8eef72-d924-5b12-9d30-15dd72d6882f','Universitas Gadjah Mada','ID')
ON CONFLICT(name,country_code) DO NOTHING;
INSERT INTO hobbies(id,category_id,code,label)
SELECT v.id::uuid,c.id,v.code,v.label FROM (VALUES
('1aca2383-551f-5ef8-8b0e-225dcf9f9230','hiking','Hiking'),
('a3b537d0-a42d-5b87-b4de-122df20f8e3f','running','Running'),
('f06148a5-a1b5-50f0-aa1d-b2b09e2b4563','cycling','Cycling'),
('5c3d8be4-9755-5a83-9ac5-cd82e835c45d','camping','Camping'),
('6f52edfa-9863-54ac-8f2d-21a72ac61f4e','swimming','Swimming'),
('0cfad5f2-1d73-536f-afdf-bcaf1f2954c6','badminton','Badminton')
) AS v(id,code,label) JOIN hobby_categories c ON c.code='outdoor'
ON CONFLICT(code) DO NOTHING;
INSERT INTO hobbies(id,category_id,code,label)
SELECT v.id::uuid,c.id,v.code,v.label FROM (VALUES
('8d9a2777-0fec-5f67-9502-d527f786310d','reading','Reading'),
('00a89fef-d3cf-59cf-bea3-b7e40d137ad6','cooking','Cooking'),
('77723c76-cded-5d53-8e3b-c82584e5dbb7','baking','Baking'),
('bc825ff8-6c15-59c0-833c-ca30de45c485','movies','Movies'),
('2b5f0a5a-8a06-518f-96c3-85154ff83dba','music','Music'),
('7e7f285d-d41a-5647-a33b-860a4a6cd3ab','photography','Photography')
) AS v(id,code,label) JOIN hobby_categories c ON c.code='indoor'
ON CONFLICT(code) DO NOTHING;
INSERT INTO hobbies(id,category_id,code,label)
SELECT v.id::uuid,c.id,v.code,v.label FROM (VALUES
('7dfa0042-2605-5f33-a226-bb0f87e2a521','board_games','Board games'),
('2c46177c-1d2c-579e-9fea-53700246a024','mobile_games','Mobile games'),
('4f42db8f-b475-5964-bd84-bad8645e5df8','pc_games','PC games'),
('cb1d6698-8316-5e45-8047-50fc5e5cd090','console_games','Console games')
) AS v(id,code,label) JOIN hobby_categories c ON c.code='gaming'
ON CONFLICT(code) DO NOTHING;
COMMIT;
