# PostgreSQL is the source of truth

Capacity, membership, follows, and registrations are enforced with foreign keys, unique indexes, and check constraints. ActiveRecord validations explain bad input. They are not the last line of defense.

Redis holds replaceable caches and the Sidekiq queue. The Go service stores a derived read model in the same Postgres instance, under the `personalization` schema. If that read model is wrong, it can be rebuilt from outbox events. It is not allowed to be the only copy of a registration.
