# dashboard-endpoints Specification

## Purpose
Lets an operator manage merchants and their endpoints from the dashboard: create, edit, enable and disable them, see a new or rotated signing secret exactly once, and find degraded endpoints.

## Requirements

### Requirement: Merchants list and page
The dashboard SHALL list merchants with their name, enabled state (as text) and creation time, with "Load more", and show a merchant page with its name, state and its endpoints, each linking to its endpoint page. An unknown merchant MUST show a not-found message.

#### Scenario: Merchants listed
- **WHEN** a signed-in operator opens the merchants page
- **THEN** the merchants are shown with name, enabled or disabled as text, and creation time, each linking to its merchant page

#### Scenario: Merchant with its endpoints
- **WHEN** an operator opens a merchant with two endpoints
- **THEN** the page shows the merchant's name and state and both endpoints' URLs, each linking to its endpoint page

#### Scenario: Unknown merchant
- **WHEN** an operator opens a merchant id that the API answers with `404`
- **THEN** the page says the merchant was not found, with a link back to the merchants list

### Requirement: Create and edit merchants
With a `write` key, the dashboard SHALL let the operator create a merchant by name, rename it, and disable or enable it, then show the result. A name the API rejects MUST show the API's message next to the name field.

#### Scenario: Merchant created
- **WHEN** an operator with a `write` key creates a merchant named "Acme"
- **THEN** `POST /api/v1/merchants` is sent with that name and the new merchant's page is shown

#### Scenario: Merchant disabled
- **WHEN** an operator disables an enabled merchant and confirms
- **THEN** `PATCH /api/v1/merchants/:id` is sent with `enabled` false and the page shows the merchant as disabled

#### Scenario: Invalid merchant name
- **WHEN** the API answers a merchant creation with `422` and an error for `name`
- **THEN** the error is shown next to the name field and no merchant page is opened

### Requirement: Endpoints list
The dashboard SHALL list endpoints with their URL, merchant name, enabled state and health, filtered by merchant and by "degraded only", with filters kept in the URL and "Load more". A degraded endpoint MUST be marked with the text "Degraded" and its consecutive failures, not by color alone.

#### Scenario: Endpoints listed
- **WHEN** a signed-in operator opens the endpoints page
- **THEN** the endpoints are shown with URL, merchant name, enabled state and health, each linking to its endpoint page

#### Scenario: Degraded endpoints only
- **WHEN** an operator turns on "degraded only"
- **THEN** the URL holds the filter, the API is asked with `degraded=true`, and each listed endpoint shows "Degraded" with its consecutive failures

#### Scenario: Endpoints of one merchant
- **WHEN** an operator picks a merchant in the filter
- **THEN** the API is asked with that `merchant_id` and only its endpoints are shown

### Requirement: Endpoint page
The dashboard SHALL show an endpoint's URL, merchant, description, event-type filters (or "All event types" when empty), enabled state, retry window, retry on 4xx, concurrency, health (degraded since, consecutive failures), when a previous secret stops signing if a rotation is in its overlap, and a link to its deliveries. An unknown endpoint MUST show a not-found message.

#### Scenario: Endpoint details
- **WHEN** an operator opens an endpoint with filters `payment.*` and `refund.created`
- **THEN** the page shows its URL, merchant, both filters, its settings and health, and a link to the deliveries list filtered by this endpoint

#### Scenario: Degraded endpoint details
- **WHEN** an operator opens a degraded endpoint with 23 consecutive failures
- **THEN** the page shows "Degraded", since when, and 23 consecutive failures

#### Scenario: Unknown endpoint
- **WHEN** an operator opens an endpoint id that the API answers with `404`
- **THEN** the page says the endpoint was not found, with a link back to the endpoints list

### Requirement: Create endpoints
With a `write` key, the dashboard SHALL offer a form to create an endpoint for a merchant with URL, description, event-type filters (comma-separated), retry window (in hours), retry on 4xx and concurrency, using the API's defaults when left unchanged. Errors the API returns for a field (such as an unsafe URL) MUST be shown next to that field.

#### Scenario: Endpoint created
- **WHEN** an operator fills in a URL and the filters `payment.*, refund.created` and submits
- **THEN** `POST /api/v1/endpoints` is sent with the merchant id, the URL and `event_types` `["payment.*", "refund.created"]`

#### Scenario: Unsafe URL rejected
- **WHEN** the API answers the creation with `422` and an error for `url`
- **THEN** the error is shown next to the URL field and the form keeps its values

### Requirement: Secret shown once
After an endpoint is created or its secret rotated, the dashboard SHALL show the secret the API returned once, with a copy action and a warning that it will not be shown again. The secret MUST NOT be kept in the query cache, browser storage or the URL, and leaving the view MUST make it unrecoverable from the dashboard.

#### Scenario: Secret after creation
- **WHEN** the API answers an endpoint creation with a secret
- **THEN** the secret is shown with a copy action and the warning, and after the operator continues to the endpoint page it is shown nowhere

#### Scenario: Secret kept out of storage
- **WHEN** a secret has been shown
- **THEN** no query cache entry, session or local storage entry and no URL contains it

### Requirement: Edit, disable and rotate endpoints
With a `write` key, the endpoint page SHALL offer editing the endpoint's fields, enabling or disabling it, and rotating its secret. Rotating MUST ask for confirmation, saying that the previous secret keeps signing for 24 hours; after it, the new secret is shown once and the page shows when the previous one stops signing.

#### Scenario: Endpoint edited
- **WHEN** an operator changes an endpoint's filters to `invoice.*` and saves
- **THEN** `PATCH /api/v1/endpoints/:id` is sent with `event_types` `["invoice.*"]` and the page shows the new filter

#### Scenario: Endpoint disabled
- **WHEN** an operator disables an endpoint
- **THEN** `PATCH /api/v1/endpoints/:id` is sent with `enabled` false and the page shows it as disabled

#### Scenario: Secret rotated
- **WHEN** an operator rotates an endpoint's secret and confirms
- **THEN** `POST /api/v1/endpoints/:id/rotate_secret` is sent once, the new secret is shown once, and the page shows when the previous secret stops signing

### Requirement: Management needs the write scope
For a key without the `write` scope, the merchants and endpoints pages SHALL hide or disable every create, edit, enable, disable and rotate action, and say that changes need the `write` scope.

#### Scenario: Read-only key
- **WHEN** an operator whose key has only `read` opens an endpoint page and the merchants page
- **THEN** no edit, disable, rotate or create action can be used, and the pages say that changes need the `write` scope
