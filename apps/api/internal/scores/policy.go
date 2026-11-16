package scores

import (
	"math"
	"time"
)

func ActorWeight(status string, createdAt time.Time, phoneVerifiedAt *time.Time, positives, total int, now time.Time) float64 {
	if status != "active" || createdAt.After(now.Add(-72*time.Hour)) || phoneVerifiedAt == nil || phoneVerifiedAt.After(now) {
		return 0
	}
	if total > 0 && float64(positives)/float64(total) > .8 {
		return .25
	}
	return 1
}
func Decay(occurredAt, now time.Time) float64 {
	age := now.Sub(occurredAt).Hours() / 24
	if age < 0 || age > 120 {
		return 0
	}
	return math.Exp2(-age / 30)
}
