package ranking

import (
	"container/heap"
	"time"

	"myforum/personalization/internal/store"
)

type Recommendation struct {
	Event store.Event
	Score int
}

// TopK keeps the best limit recommendations offered to it, so ranking holds limit events in memory however many
// candidates there are (MF-204). A limit of 0 or less keeps everything.
type TopK struct {
	limit    int
	followed map[int64]struct{}
	location string
	now      time.Time
	worst    *worstFirst
}

func NewTopK(limit int, profile store.Profile, now time.Time) *TopK {
	followed := map[int64]struct{}{}
	for _, topicID := range profile.TopicIDs {
		followed[topicID] = struct{}{}
	}
	return &TopK{limit: limit, followed: followed, location: profile.Location, now: now, worst: &worstFirst{}}
}

// Offer scores one candidate and keeps it if it is among the best so far.
func (t *TopK) Offer(event store.Event) {
	if event.Status != "published" || !event.StartsAt.After(t.now) {
		return
	}
	candidate := Recommendation{Event: event, Score: t.score(event)}
	if t.limit <= 0 || t.worst.Len() < t.limit {
		heap.Push(t.worst, candidate)
		return
	}
	if better(candidate, (*t.worst)[0]) {
		(*t.worst)[0] = candidate
		heap.Fix(t.worst, 0)
	}
}

// Results returns the kept recommendations, best first.
func (t *TopK) Results() []Recommendation {
	ranked := make([]Recommendation, t.worst.Len())
	for index := len(ranked) - 1; index >= 0; index-- {
		ranked[index] = heap.Pop(t.worst).(Recommendation)
	}
	return ranked
}

func (t *TopK) score(event store.Event) int {
	score := 0
	for _, topicID := range event.TopicIDs {
		if _, ok := t.followed[topicID]; ok {
			score += 10
		}
	}
	if t.location != "" && event.Location == t.location {
		score += 5
	}
	if event.StartsAt.Before(t.now.Add(14 * 24 * time.Hour)) {
		score += 3
	}
	if event.Capacity > 0 {
		score += int(float64(event.ReservedSpots) / float64(event.Capacity) * 5)
	}
	return score
}

// Rank ranks a whole list; the service streams through TopK instead.
func Rank(events []store.Event, profile store.Profile, now time.Time, limit int) []Recommendation {
	top := NewTopK(limit, profile, now)
	for _, event := range events {
		top.Offer(event)
	}
	return top.Results()
}

// better is the ranking order: higher score, then sooner, then lower id, so ties never depend on read order.
func better(a, b Recommendation) bool {
	if a.Score != b.Score {
		return a.Score > b.Score
	}
	if !a.Event.StartsAt.Equal(b.Event.StartsAt) {
		return a.Event.StartsAt.Before(b.Event.StartsAt)
	}
	return a.Event.ID < b.Event.ID
}

// worstFirst is a heap whose root is the worst kept recommendation, the one to drop when a better one arrives.
type worstFirst []Recommendation

func (h worstFirst) Len() int           { return len(h) }
func (h worstFirst) Less(i, j int) bool { return better(h[j], h[i]) }
func (h worstFirst) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *worstFirst) Push(x any)        { *h = append(*h, x.(Recommendation)) }
func (h *worstFirst) Pop() any {
	old := *h
	last := old[len(old)-1]
	*h = old[:len(old)-1]
	return last
}
