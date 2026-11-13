# Frontend (Angular 19)

- Standalone components with signals. HTTP goes through `ForumApi` (`src/app/core/forum-api.ts`); types live in `core/models.ts` and mirror the Rails JSON exactly.
- The server decides. Never compute permission or availability in the client when the API returns it (`status`, `my_registration`, error `code`). Show what the server said, including its error messages, inline next to the action. There is no toast component.
- **Route changes reuse the component.** When a page reads a route param, reset per-record state (messages, errors, loading flags) when the param changes, not only on init.
- A disabled button gets no hover or focus, so it cannot carry a tooltip: put the explanation in visible text next to it.
- Tests: `npm test -- --watch=false --browsers=ChromeHeadless` (Karma runs the whole suite; there is no fast single-spec run). The edit hook type-checks with `tsc` instead. Each component spec covers what the user sees for each server state and each error code.
