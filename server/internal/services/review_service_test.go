package services

import (
	"testing"
	"time"
)

func TestMasteredWordLeavesScheduleAtEveryStage(t *testing.T) {
	now := time.Date(2026, 9, 20, 16, 0, 0, 0, time.Local)
	for _, step := range []int{0, 1, 2, 3, 4} {
		nextStep, status, next := nextWordReviewState(step, "mastered", now)
		if status != "mastered" || next != nil || nextStep != step+1 {
			t.Fatalf("step %d: mastered word must leave task pool; got %d %s %v", step, nextStep, status, next)
		}
	}
}

func TestUnfamiliarWordReturnsTomorrow(t *testing.T) {
	now := time.Date(2026, 12, 31, 23, 59, 0, 0, time.Local)
	step, status, next := nextWordReviewState(2, "again", now)
	want := time.Date(2027, 1, 1, 0, 0, 0, 0, time.Local)
	if step != 2 || status != "learning" || next == nil || !next.Equal(want) {
		t.Fatalf("unfamiliar word should return tomorrow: %d %s %v", step, status, next)
	}
}

func TestReviewSummaryAfterMasteringWords(t *testing.T) {
	cases := []struct{ due, completed, recommended, backlog int }{
		{50, 0, 30, 20},
		{20, 30, 0, 20},
		{0, 50, 0, 0},
		{10, 0, 10, 0},
	}
	for _, c := range cases {
		got := buildWordReviewTodaySummary(c.due, c.completed, 1)
		if got.DueCount != c.due || got.CompletedCount != c.completed || got.RecommendedCount != c.recommended || got.BacklogCount != c.backlog || got.DailyTarget != 30 {
			t.Fatalf("due=%d completed=%d: unexpected summary %+v", c.due, c.completed, got)
		}
	}
}
