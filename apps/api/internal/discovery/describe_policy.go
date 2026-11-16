package discovery

import "math"

const (
	DescribeRelevanceWeight = 0.6
	DescribeQualityWeight   = 0.25
	DescribeDistanceWeight  = 0.15
)

func DescribeNumericTolerance(field string, value float64) float64 {
	switch field {
	case "age", "height_cm":
		return 2
	case "distance_km":
		return math.Min(value*0.1, 5)
	default:
		return 0
	}
}
