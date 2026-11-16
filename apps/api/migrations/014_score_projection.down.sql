CREATE OR REPLACE VIEW discovery_quality AS SELECT NULL::uuid AS candidate_id,NULL::text AS segment_key,0::double precision AS likes_w,0::double precision AS passes_w,0.5::double precision AS percentile,0.75::double precision AS reply_rate,NULL::double precision AS prior_mean,0::bigint AS completed_matches WHERE false;
DROP TABLE score_rebuild_runs,score_reply_stats,score_reply_windows,score_values,score_segment_priors,score_actor_weights,score_projection_receipts;
DROP INDEX swipe_events_actor_recent,swipe_events_target_segment;
ALTER TABLE accounts DROP COLUMN phone_verified_at;
