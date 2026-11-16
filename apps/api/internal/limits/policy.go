package limits

import "time"

type Grant struct {
	Likes    int `json:"likes"`
	Searches int `json:"searches"`
}

func Grants(complete, pro bool) Grant {
	g := Grant{Likes: 15, Searches: 3}
	if complete {
		g.Likes = 30
	}
	if pro {
		g.Searches = 20
	}
	return g
}

func Bucket(now time.Time) (string, time.Time) {
	local := now.In(time.FixedZone("WIB", 7*60*60))
	reset := time.Date(local.Year(), local.Month(), local.Day()+1, 0, 0, 0, 0, local.Location())
	return local.Format("2006-01-02"), reset.UTC()
}
