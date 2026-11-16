package discovery

import (
	"sort"
	"time"
)

func AssembleDeck(pool []CandidateInput, p Policy, pro bool) []CandidateInput {
	var oldestPriority string
	var oldestTime time.Time
	for _, c := range pool {
		if c.Priority {
			if oldestPriority == "" || c.PriorityAt.Before(oldestTime) {
				oldestPriority = c.ID
				oldestTime = c.PriorityAt
			}
		}
	}
	sort.SliceStable(pool, func(i, j int) bool {
		if pool[i].Score == pool[j].Score {
			return pool[i].ID < pool[j].ID
		}
		return pool[i].Score > pool[j].Score
	})
	out := []CandidateInput{}
	seen := map[string]bool{}
	take := func(c CandidateInput, bucket string) {
		if !seen[c.ID] && len(out) < 20 {
			seen[c.ID] = true
			c.Bucket = bucket
			out = append(out, c)
		}
	}
	for _, c := range pool {
		if c.ID == oldestPriority {
			take(c, "priority")
			break
		}
	}
	fresh := 0
	for _, c := range pool {
		if c.Fresh && fresh < p.FreshSlots && !seen[c.ID] && c.Bypass != "incoming_super_like" {
			take(c, "fresh")
			fresh++
		}
	}
	top := p.FreeTopHalf
	if pro {
		top = p.ProTopHalf
	}
	for _, c := range out {
		if c.Percentile >= 0.5 {
			top--
		}
	}
	top = max(0, top)
	high, low := []CandidateInput{}, []CandidateInput{}
	for _, c := range pool {
		if c.Bypass == "incoming_super_like" && c.ID != oldestPriority {
			continue
		}
		if seen[c.ID] {
			continue
		}
		if c.Percentile >= 0.5 {
			high = append(high, c)
		} else {
			low = append(low, c)
		}
	}
	hi, lo := 0, 0
	for len(out) < 20 && (hi < len(high) || lo < len(low)) {
		wantHigh := hi < top && (len(out)*top/20 >= hi || lo >= len(low))
		if wantHigh && hi < len(high) {
			take(high[hi], "top_half")
			hi++
		} else if lo < len(low) {
			take(low[lo], "lower_half")
			lo++
		} else {
			take(high[hi], "backfill")
			hi++
		}
	}
	return out
}
