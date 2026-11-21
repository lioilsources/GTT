package progress

import (
	"testing"
	"time"
)

func TestWindowRatesAndDaily(t *testing.T) {
	items := []Item{
		{Size: "L", Status: Hotovo, Done: "2026-11-18T10:00"},
		{Size: "M", Status: Ceka, Done: "2026-11-20T10:00"},
		{Size: "S", Status: Todo},
	}
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.Local)
	daily := DailyPoints(items)
	if daily[time.Date(2026, 11, 18, 0, 0, 0, 0, time.Local)] != 4 {
		t.Fatalf("daily %v", daily)
	}
	fast, slow, ok := WindowRates(daily, now)
	// windows: 18–20 = 6/3, 19–21 = 2/3
	if !ok || fast != 2 || slow < 0.66 || slow > 0.67 {
		t.Fatalf("fast %v slow %v", fast, slow)
	}
}

func TestCheckRejectsDoneWithoutEvidence(t *testing.T) {
	f := &File{Milestones: []string{"M0"}, Items: []Item{{ID: "a", Milestone: "M0", Size: "S", Status: Hotovo, Done: "2026-11-21T10:00"}}}
	if f.check() == nil {
		t.Fatal("hotovo without evidence must fail")
	}
	f.Items[0].Evidence = "go test"
	if err := f.check(); err != nil {
		t.Fatal(err)
	}
	f.Items[0].Size = "XL"
	if f.check() == nil {
		t.Fatal("unknown size must fail")
	}
}
