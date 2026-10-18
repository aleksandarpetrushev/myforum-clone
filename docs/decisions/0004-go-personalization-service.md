# Recommendations live in a Go service

Ranking does not need to sit inside the request that registers someone. The Go service accepts domain events, keeps a small read model, and answers `GET /recommendations`.

The first ranker is a deterministic score: topic overlap, location, a two-week boost, and how full the event is. That function is isolated so a later exercise can replace it with a model without rewriting ingest or HTTP.
