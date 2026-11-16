DROP VIEW discovery_pair_exclusions;
DROP TABLE discovery_activity,user_blocks;
ALTER TABLE profiles DROP CONSTRAINT profiles_age_preference_order,
 DROP COLUMN min_age,DROP COLUMN max_age,DROP COLUMN radius_km;
