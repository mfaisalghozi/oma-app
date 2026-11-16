DROP VIEW discovery_incoming_priority,discovery_quality;
DROP TABLE candidate_daily_exposures,discovery_exposures,deck_cursors,deck_cache_cards,deck_cache;
DROP TRIGGER discovery_location_revision ON user_locations;
DROP FUNCTION discovery_location_revision();
DROP TRIGGER discovery_profile_revision ON profiles;
DROP FUNCTION discovery_profile_revision();
ALTER TABLE user_locations DROP COLUMN location_version;
ALTER TABLE profiles DROP COLUMN revision,DROP COLUMN preference_revision,DROP COLUMN random_key;
