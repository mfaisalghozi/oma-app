package discovery

import (
	"math"
	"math/rand/v2"
)

func gamma(r *rand.Rand, a float64) float64 {
	if a < 1 {
		return gamma(r, a+1) * math.Pow(r.Float64(), 1/a)
	}
	d := a - 1.0/3
	c := 1 / math.Sqrt(9*d)
	for {
		x := r.NormFloat64()
		v := 1 + c*x
		if v <= 0 {
			continue
		}
		v = v * v * v
		u := r.Float64()
		if u < 1-0.0331*x*x*x*x || math.Log(u) < 0.5*x*x+d*(1-v+math.Log(v)) {
			return d * v
		}
	}
}
