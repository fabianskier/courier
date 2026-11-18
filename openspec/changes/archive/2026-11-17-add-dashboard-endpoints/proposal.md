# Proposal

## Why

Operators can see deliveries in the dashboard (step 10) but still need `curl` to add a merchant, register an endpoint, change its filters or rotate its secret, and nothing shows which endpoints are degraded (FR-27, covering FR-6, FR-7, FR-9 and FR-17). The REST API already does all of it, so this change is the dashboard side only.

## What Changes

- **Merchants pages**: a merchants list ("Load more"), a form to create one, and a merchant page to rename, disable or enable it, with its endpoints.
- **Endpoints pages**: an endpoints list filtered by merchant and by "degraded only", where each endpoint shows its URL, merchant, enabled state, health (degraded, consecutive failures) as text; and an endpoint page with its settings, health, secret rotation state and a link to its deliveries.
- **Create an endpoint**: URL, description, event-type filters, retry window, retry on 4xx and concurrency. The signing secret the API returns is shown once, with a copy action and a warning; it is never cached, stored or put in the URL.
- **Edit an endpoint**: the same fields plus enabled; validation errors from the API are shown next to their fields.
- **Rotate the secret**: with a confirmation; the new secret is shown once, together with when the previous one stops signing.
- **Write scope**: creating, editing, enabling and rotating are offered only to keys with `write`; read keys see the pages without those actions.
- **API client**: requests with a JSON body (`POST`, `PATCH`) and the `details` of `422` errors.
- **Not in this change**: deleting merchants or endpoints (the API has no delete), live updates (step 12), registering secrets with the demo receiver from the dashboard, and endpoints beyond the first 100 in lookups.

## Capabilities

### New Capabilities
- `dashboard-endpoints`: the dashboard's merchants and endpoints pages: lists, creation, editing, enabling and disabling, the secret shown once, secret rotation and degraded endpoints.

### Modified Capabilities
None. The API behaviour these pages use is already specified in `merchants`, `webhook-endpoints` and `endpoint-health`.

## Impact

- Frontend only: `src/features/merchants/`, `src/features/endpoints/`, routes under `src/routes/_app/`, navigation links, `apiFetch` body support and `ApiError.details`; tests in `frontend/tests/` with MSW. No new npm dependencies.
- The merchants and endpoints lookups from step 10 are invalidated after every change, so names and URLs stay current.
- No backend or database changes. Existing tests are not modified.
