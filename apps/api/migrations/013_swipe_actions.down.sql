CREATE OR REPLACE VIEW discovery_pair_exclusions AS SELECT NULL::uuid AS viewer_id,NULL::uuid AS candidate_id WHERE false;
CREATE OR REPLACE VIEW discovery_incoming_priority AS SELECT NULL::uuid AS viewer_id,NULL::uuid AS candidate_id,NULL::timestamptz AS created_at WHERE false;
DROP TABLE swipe_events;
DROP FUNCTION immutable_swipe_event();
DROP TABLE matches;
DROP TABLE super_like_balances;
DROP TABLE swipe_requests;
DROP TABLE profile_interactions;
