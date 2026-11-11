CREATE TABLE gender_options (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE gender_options ENABLE ROW LEVEL SECURITY;
CREATE TABLE pronoun_options (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE pronoun_options ENABLE ROW LEVEL SECURITY;
CREATE TABLE show_me_options (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE show_me_options ENABLE ROW LEVEL SECURITY;
CREATE TABLE looking_for_options (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE looking_for_options ENABLE ROW LEVEL SECURITY;
CREATE TABLE religions (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE religions ENABLE ROW LEVEL SECURITY;
CREATE TABLE personality_types (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE personality_types ENABLE ROW LEVEL SECURITY;
CREATE TABLE hobby_categories (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE hobby_categories ENABLE ROW LEVEL SECURITY;
CREATE TABLE universities (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 name TEXT NOT NULL,
 country_code CHAR(2) NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true,
 UNIQUE(name,country_code)
);
CREATE TABLE hobbies (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 category_id UUID NOT NULL REFERENCES hobby_categories(id),
 code TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE universities ENABLE ROW LEVEL SECURITY;
ALTER TABLE hobbies ENABLE ROW LEVEL SECURITY;
-- Values explicitly present in the technical document. Remaining catalogs need approval.
INSERT INTO gender_options(code,label) VALUES('woman','Woman'),('man','Man');
INSERT INTO show_me_options(code,label) VALUES('woman','Woman'),('man','Men'),('everyone','Everyone');
INSERT INTO pronoun_options(code,label) VALUES('he_him','He/Him');
INSERT INTO personality_types(code,label) VALUES
('INTJ','INTJ'),
('INTP','INTP'),
('ENTJ','ENTJ'),
('ENTP','ENTP'),
('INFJ','Advocate'),
('INFP','INFP'),
('ENFJ','ENFJ'),
('ENFP','ENFP'),
('ISTJ','ISTJ'),
('ISFJ','ISFJ'),
('ESTJ','ESTJ'),
('ESFJ','ESFJ'),
('ISTP','ISTP'),
('ISFP','ISFP'),
('ESTP','ESTP'),
('ESFP','ESFP');
