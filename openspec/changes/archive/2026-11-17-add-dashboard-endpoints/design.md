# Design

## Context

See proposal.md for the motivation. What exists:

- **API.** `GET|POST /api/v1/merchants`, `GET|PATCH /api/v1/merchants/:id` (`name`, `enabled`); `GET|POST /api/v1/endpoints` (list filters `merchant_id`, `degraded=true|false`), `GET|PATCH /api/v1/endpoints/:id`, `POST /api/v1/endpoints/:id/rotate_secret`. Create and rotate answer with the endpoint plus `secret`; nothing else returns it. Endpoint JSON has `url`, `description`, `event_types`, `enabled`, `retry_window_seconds` (60..86,400, default 86,400), `retry_on_4xx`, `max_concurrency` (1..50, default 10), `consecutive_failures`, `degraded`, `degraded_at`, `previous_secret_expires_at`. A changeset error answers `422` with `{"error": {"code": "invalid", "message", "details": {"<field>": ["<message>"]}}}`. Reads need `read`, changes `write`.
- **SPA** (step 10). `apiFetch(path, { method: 'GET' | 'POST', query, signal, key })` with no request body, and `ApiError { status, code, message }`; `useMe()` gives the key's scopes; `src/lib/api/lookups.ts` caches `GET /merchants?limit=100` and `GET /endpoints?limit=100` under `queryKeys.merchants` and `queryKeys.endpoints`; `StatusBadge`, `LoadError`, `format.ts`; "Load more" lists with Zod-validated search in the URL; MSW helpers in `frontend/tests/support/`.
- **Gate.** About 800 changed lines and 20 files per task; `routeTree.gen.ts` and `package-lock.json` are not counted; existing files under `frontend/tests/` are protected.

## Goals / Non-Goals

**Goals:** pages that reuse the step 10 patterns (lists, filters in the URL, states, scope checks); secrets that exist only in component state for as long as they are shown; API validation messages next to their fields.

**Non-Goals:** client-side validation beyond required fields and number ranges (the API is the source of truth), deleting, bulk actions, and registering secrets with the demo receiver.

## Decisions

**Client.** `apiFetch` gains `method: 'PATCH'` and `body?: unknown` (sent as JSON with `content-type: application/json`), and `ApiError` gains `details?: Record<string, string[]>` from the error body. Existing calls do not change.

**Routes.**

```text
_app/merchants.index.tsx            list, "New merchant" (write)
_app/merchants.$merchantId.tsx      name, state, rename/disable (write), endpoints, "New endpoint" (write)
_app/endpoints.index.tsx            list, filters merchant_id and degraded (Zod search)
_app/endpoints.new.tsx              create form; search merchant_id preselects the merchant
_app/endpoints.$endpointId.tsx      details, health, edit/disable/rotate (write), link to /deliveries?endpoint_id=
```

Navigation gains "Merchants" and "Endpoints".

**Forms.** React Hook Form + Zod with the shadcn `Field` components, as on sign-in. Event-type filters are one text input, split on commas and trimmed, empty entries dropped. The retry window is entered in hours (a number with up to two decimals, default 24) and sent as `Math.round(hours * 3600)` seconds; the API's 60..86,400 rule is the check, and its message is shown on the field. A `422` with `details` sets each message on its field with `setError`; a `422` without details, or any other error, shows an `Alert` with the API message. One `applyApiErrors(form, error)` helper does this for every form.

**Mutations.** Each change is a `useMutation`. On success it invalidates `queryKeys.merchants`, `queryKeys.endpoints` (lookups and lists) and the edited item's detail key, then navigates or shows the updated page. Enable/disable is a button with a confirmation dialog for disabling (it stops new deliveries), and a plain button for enabling.

**Secrets.** Create and rotate call `apiFetch` in `mutationFn`; `onSuccess` copies `secret` into component state and the mutation is `reset()` right away, so the response does not stay in TanStack Query's mutation cache; the endpoint data without `secret` is written to the detail key with `setQueryData`. A `SecretReveal` component shows the secret in a read-only monospace field with "Copy" (`navigator.clipboard.writeText`) and the warning "This secret will not be shown again. Store it now." After creation it replaces the form until "Continue to the endpoint"; after rotation it is shown in the rotation dialog until it is closed, and the page then shows "Previous secret signs until <time>".

**Degraded endpoints.** A `HealthBadge` (icon + text: "Healthy" or "Degraded", with "N consecutive failures") is used in the list and on the endpoint page. The "degraded only" filter is a checkbox stored as `degraded=true` in the URL and sent as is.

**Write scope.** Pages read `useMe().scopes`. Without `write`: no "New merchant" or "New endpoint" buttons, edit forms render read-only values, disable/enable and rotate buttons are not rendered, and a short note says "Changes need the write scope." `/endpoints/new` with a read key shows that note instead of the form.

**Tests.** One test file per task in `frontend/tests/`, named after the spec. New fixtures go in new files under `frontend/tests/support/` (merchant and endpoint factories with `degraded` and `secret` variants). "Secret kept out of storage" is checked by scanning `queryClient` (queries and mutations), `sessionStorage`, `localStorage` and `window.location.href` for the secret after it was shown.

## Risks / Trade-offs

- [The secret is visible on screen and in the clipboard] → expected for "shown once"; the dashboard keeps no copy, and the warning says to store it.
- [An endpoint created from the dashboard is not registered with the demo receiver] → its deliveries fail signature checks in the demo; the README's demo uses seeded endpoints, and the docs task notes it.
- [More than 100 merchants in the create form's merchant select] → the same limit as step 10's lookups; acceptable for the demo.
