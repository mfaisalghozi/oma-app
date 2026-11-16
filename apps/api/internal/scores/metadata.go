package scores

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

// Only a trusted Auth synchronizer may supply this value; JWT claims and clients are not verification evidence.
func RecordPhoneVerificationTx(ctx context.Context, tx *sql.Tx, userID string, verifiedAt *time.Time) error {
	if tx == nil {
		return errors.New("transaction required")
	}
	if verifiedAt != nil && verifiedAt.After(time.Now()) {
		return errors.New("future phone verification")
	}
	result, err := tx.ExecContext(ctx, `UPDATE accounts SET phone_verified_at=$2 WHERE user_id=$1`, userID, verifiedAt)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n != 1 {
		return sql.ErrNoRows
	}
	return nil
}

type ReplyWindow struct {
	MatchID, OpenerSenderID string
	OpenedAt                time.Time
	FirstReplyAt            *time.Time
}

// Chat must pass server message metadata for the first qualifying reply, never message bodies or client receipts.
func RecordReplyWindowTx(ctx context.Context, tx *sql.Tx, w ReplyWindow) error {
	if tx == nil || w.OpenedAt.IsZero() || w.OpenedAt.After(time.Now()) || w.FirstReplyAt != nil && (w.FirstReplyAt.Before(w.OpenedAt) || w.FirstReplyAt.After(time.Now())) {
		return errors.New("invalid reply metadata")
	}
	var respondent string
	if err := tx.QueryRowContext(ctx, `SELECT CASE WHEN user_low=$2 THEN user_high ELSE user_low END FROM matches WHERE id=$1 AND $2 IN(user_low,user_high) AND created_at<=$3`, w.MatchID, w.OpenerSenderID, w.OpenedAt).Scan(&respondent); err != nil {
		return err
	}
	result, err := tx.ExecContext(ctx, `INSERT INTO score_reply_windows(match_id,opener_sender_id,respondent_id,opened_at,first_reply_at) VALUES($1,$2,$3,$4,$5)
 ON CONFLICT(match_id) DO UPDATE SET first_reply_at=CASE WHEN score_reply_windows.first_reply_at IS NULL THEN EXCLUDED.first_reply_at WHEN EXCLUDED.first_reply_at IS NULL THEN score_reply_windows.first_reply_at ELSE LEAST(score_reply_windows.first_reply_at,EXCLUDED.first_reply_at) END
 WHERE score_reply_windows.opener_sender_id=EXCLUDED.opener_sender_id AND score_reply_windows.opened_at=EXCLUDED.opened_at`, w.MatchID, w.OpenerSenderID, respondent, w.OpenedAt, w.FirstReplyAt)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n != 1 {
		return errors.New("conflicting reply opener")
	}
	return nil
}
