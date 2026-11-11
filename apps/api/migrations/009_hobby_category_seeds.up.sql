-- PRD M08 defines these three hobby categories. Full hobby catalogs remain pending.
INSERT INTO hobby_categories(id,code,label) VALUES
('659222d0-8f3d-551b-95f1-dab9ed7bf7d4','outdoor','Outdoor'),
('ab4b40dc-1bdb-5098-82da-ef0607f5d0bd','indoor','Indoor'),
('9c97ded2-ea2b-59c4-aae8-ef1f2bc99d8a','gaming','Gaming')
ON CONFLICT(code) DO NOTHING;
