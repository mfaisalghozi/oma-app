package discovery_test

import (
	"fmt"
	"oma/apps/api/internal/discovery"
	"testing"
)

func TestDeckMixCountsPriorityAndFreshCardsInTopHalfBudget(t *testing.T) {
	pool := []discovery.CandidateInput{{ID: "priority", Priority: true, Percentile: .9, Score: 1}, {ID: "fresh-a", Fresh: true, Percentile: .8, Score: .9}, {ID: "fresh-b", Fresh: true, Percentile: .8, Score: .8}}
	for i := 0; i < 20; i++ {
		pool = append(pool, discovery.CandidateInput{ID: fmt.Sprintf("low-%d", i), Percentile: .2, Score: .7 - float64(i)/100})
	}
	for i := 0; i < 10; i++ {
		pool = append(pool, discovery.CandidateInput{ID: fmt.Sprintf("high-%d", i), Percentile: .8, Score: .6 - float64(i)/100})
	}
	deck := discovery.AssembleDeck(pool, discovery.Policy{FreshSlots: 2, FreeTopHalf: 5}, false)
	if len(deck) != 20 || deck[0].ID != "priority" {
		t.Fatalf("invalid deck size/pin %#v", deck)
	}
	high := 0
	seen := map[string]bool{}
	for _, c := range deck {
		if seen[c.ID] {
			t.Fatal("duplicate card")
		}
		seen[c.ID] = true
		if c.Percentile >= .5 {
			high++
		}
	}
	if high != 5 {
		t.Fatalf("top-half budget counted fresh and priority twice: got%d want5", high)
	}
}
