package services

import "testing"

func TestWordReviewIntervalDays(t *testing.T) {
	cases := map[int]int{
		1: 2,
		2: 4,
		3: 7,
		4: 7,
	}
	for step, want := range cases {
		if got := wordReviewIntervalDays(step); got != want {
			t.Fatalf("step=%d got=%d want=%d", step, got, want)
		}
	}
}
