# Event visibility is checked live, and the list cache is keyed by membership

Status: accepted. Recorded on 2026-10-29 for `4b0554c`, which made the change on 2026-10-18.

## Summary

Who may see an event is decided on every request from the current organization memberships in Postgres, never from a stored permission. The cached first page of upcoming events is keyed by a fingerprint of the user's memberships and a global list version, so a membership change takes effect on the next request. We will revisit this when visibility needs rules that memberships cannot express, or when the list cache stops getting hits.

## Context

`4b0554c` added `organization_restricted` events: visible to members of the organizations listed in `event_allowed_organizations`, and to admins of the organizing organization. That made the event list depend on who is asking. Before it, one cached list served everyone.

Memberships change outside the event code: an admin removes a member, or a script runs `delete_all`. Any rule that depends on noticing those writes misses some of them.

## Decision

- `EventPolicy` is the only place the rule lives. `Scope#resolve` filters lists, search and registration history in SQL; `show?` checks one event. Listing, search, detail and creating a registration all go through it. A direct id that fails the scope returns 404, not 403.
- The Go service applies the same rule. `Candidates` reads live `events`, `event_allowed_organizations` and `organization_memberships` rows; it never trusts its own projection for eligibility.
- Event detail JSON is cached once per event for 10 minutes and served only after `show?` allows the request.
- The unfiltered first page of upcoming events is cached per user for 1 minute under `events/upcoming/v2/u<user>/m<fingerprint>/e<epoch>`.
  - `fingerprint` is a hash of the user's `(organization_id, role)` rows, read from Postgres on each request. Any membership change, however it was written, gives a new key.
  - `epoch` is a global counter bumped after any event or allowed-organization write. Old keys expire by TTL.
- Filtered searches are not cached.

## Alternatives

| Option | Why not |
|---|---|
| Delete a user's cached list when their membership changes | Callback-bypassing writes (`delete_all`, SQL, another service) would leave a user seeing events they lost access to for the cache TTL |
| One cached list per combination of organizations | Fewer entries, but the key still needs the user's memberships, and admins of the organizer see drafts, so the grouping is not much smaller than per user |
| Store a per-user list of visible event ids | A second copy of the rule that has to be rebuilt on every membership and event change |
| No list cache | Simplest and always correct. Kept the cache because the first page is the most requested response; this ADR's reversal condition says when to drop it |

## Consequences

- A membership change is visible on the next request with no invalidation code.
- Each cached list request costs one indexed membership query to build the key.
- Every event write bumps the global epoch, and that includes each registration, because `Events::Register` updates `reserved_spots` and `Event` invalidates on every update. Under steady registration traffic, most cached pages are replaced before anyone reads them again.
- Losing visibility does not lose a registration: `GET /api/me/registrations` and cancel still work, without the event's title, time or location.

## Reverse if

- **Cache hit rate:** the upcoming-list cache hit rate stays below 50% for a week at production traffic, most likely because registrations keep bumping the epoch. Then either stop bumping the epoch for `reserved_spots`-only updates and show seat counts from a separate uncached call, or drop the list cache.
- **Richer rules:** visibility needs a rule that organization membership cannot express, such as invite lists, per-person bans, or time-boxed access. Then the fingerprint no longer captures everything the list depends on, and the cache key, `EventPolicy` and Go `Candidates` must change together.
