# Domain events leave through a transactional outbox

Registration, follow, and event update write an `outbox_events` row in the same transaction as the change. A Sidekiq job publishes pending rows to in-process handlers and to the Go service over HTTP.

There is no broker yet. The dispatcher is a small object so a later broker can replace the HTTP and job calls without changing `Events::Register`. Handlers are idempotent because the poller can deliver a row more than once if it crashes after side effects and before marking the row published.
