CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
CREATE TABLE profiles (
 user_id UUID PRIMARY KEY REFERENCES accounts(user_id),
 full_name VARCHAR(100) NOT NULL CHECK(char_length(full_name)>=2),
 birthdate DATE NOT NULL,
 gender_id UUID NOT NULL REFERENCES gender_options(id),
 pronoun_id UUID REFERENCES pronoun_options(id),
 show_me_option_id UUID NOT NULL REFERENCES show_me_options(id),
 bio VARCHAR(255) NOT NULL,
 height_cm SMALLINT NOT NULL CHECK(height_cm BETWEEN 100 AND 250),
 weight_kg SMALLINT NOT NULL CHECK(weight_kg BETWEEN 25 AND 300),
 university_id UUID REFERENCES universities(id),
 ambition VARCHAR(500),
 religion_id UUID REFERENCES religions(id),
 personality_type_id UUID REFERENCES personality_types(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE profile_looking_for (
 user_id UUID NOT NULL REFERENCES profiles(user_id),
 looking_for_id UUID NOT NULL REFERENCES looking_for_options(id),
 PRIMARY KEY(user_id,looking_for_id)
);
CREATE TABLE profile_hobbies (
 user_id UUID NOT NULL REFERENCES profiles(user_id),
 hobby_id UUID NOT NULL REFERENCES hobbies(id),
 PRIMARY KEY(user_id,hobby_id)
);
CREATE TABLE user_locations (
 user_id UUID PRIMARY KEY REFERENCES profiles(user_id),
 location public.GEOGRAPHY(POINT,4326) NOT NULL,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_user_locations_location ON user_locations USING GIST(location);
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_looking_for ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_hobbies ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_locations ENABLE ROW LEVEL SECURITY;
