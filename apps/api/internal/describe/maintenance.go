package describe

import "context"

func (s *Service) PruneRequestKeys(ctx context.Context) (int64, error) {
	result, err := s.DB.ExecContext(ctx, `WITH expired AS (SELECT owner_id,key_hash FROM describe_search_request_keys WHERE expires_at<=$1 ORDER BY expires_at,owner_id,key_hash LIMIT 1000 FOR UPDATE SKIP LOCKED) DELETE FROM describe_search_request_keys k USING expired e WHERE k.owner_id=e.owner_id AND k.key_hash=e.key_hash`, s.now())
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}
