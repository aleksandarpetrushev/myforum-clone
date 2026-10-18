package ranking

import (
	"sort"
	"time"

	"myforum/personalization/internal/store"
)

type Recommendation struct {
	Event store.Event
	Score int
}

func Rank(events []store.Event, profile store.Profile, now time.Time, limit int) []Recommendation {
	followed := map[int64]struct{}{}
	for _, topicID := range profile.TopicIDs {
		followed[topicID] = struct{}{}
	}

	ranked := make([]Recommendation, 0, len(events))
	for _, event := range events {
		if event.Status != "published" || !event.StartsAt.After(now) {
			continue
		}
		score := 0
		for _, topicID := range event.TopicIDs {
			if _, ok := followed[topicID]; ok {
				score += 10
			}
		}
		if profile.Location != "" && event.Location == profile.Location {
			score += 5
		}
		if event.StartsAt.Before(now.Add(14 * 24 * time.Hour)) {
			score += 3
		}
		if event.Capacity > 0 {
			score += int(float64(event.ReservedSpots) / float64(event.Capacity) * 5)
		}
		ranked = append(ranked, Recommendation{Event: event, Score: score})
	}

	sort.SliceStable(ranked, func(i, j int) bool {
		if ranked[i].Score == ranked[j].Score {
			return ranked[i].Event.StartsAt.Before(ranked[j].Event.StartsAt)
		}
		return ranked[i].Score > ranked[j].Score
	})

	if limit > 0 && len(ranked) > limit {
		ranked = ranked[:limit]
	}
	return ranked
}
