# dashboard-access Specification

## Purpose
Lets an operator open the dashboard with an existing API key, keeps that key only for the browser session, and sends the operator back to sign-in when the key stops working.

## Requirements

### Requirement: Data pages need a key
The dashboard SHALL show the sign-in page when no key is stored and the operator opens a page that shows courier data, and return the operator to that page after signing in. The overview stays open without a key and links to sign-in.

#### Scenario: Overview without a key
- **WHEN** an operator with no stored key opens the overview
- **THEN** the overview is shown with a link to sign in, and no API request is sent

#### Scenario: Valid key accepted
- **WHEN** an operator with no stored key opens the deliveries page, enters a valid key and submits
- **THEN** the key is checked with `GET /api/v1/me`, stored, and the deliveries page is shown

### Requirement: Sign in with an API key
The sign-in page SHALL ask for an API key and check it with `GET /api/v1/me` before storing it. A key the API rejects MUST NOT be stored, and the page MUST say that the key was not accepted. A failed check for any other reason (network, server error) MUST say that courier could not be reached, without storing the key.

#### Scenario: Rejected key
- **WHEN** an operator submits a key that `GET /api/v1/me` answers with `401`
- **THEN** the sign-in page stays, says the key was not accepted, and nothing is stored

#### Scenario: Courier unreachable
- **WHEN** the check of a submitted key fails with a network error or a `5xx`
- **THEN** the sign-in page says courier could not be reached, and nothing is stored

### Requirement: Key kept for the browser session only
The dashboard SHALL keep the key in session storage only: never in local storage, cookies, the URL or logs. It MUST send the key only as an `Authorization: Bearer` header to courier's own API, and show which key is in use (its name and scopes) in the layout.

#### Scenario: Key survives a reload
- **WHEN** a signed-in operator reloads the page
- **THEN** the dashboard uses the stored key without asking again, and the layout shows the key's name and scopes

#### Scenario: Key stays out of the URL and local storage
- **WHEN** an operator signs in and browses the dashboard
- **THEN** the key is in session storage only, and no URL or local storage entry contains it

### Requirement: Sign out
The dashboard SHALL offer a sign-out action that removes the stored key, clears all cached API data and shows the sign-in page.

#### Scenario: Signed out
- **WHEN** a signed-in operator signs out
- **THEN** the stored key and cached data are gone and the sign-in page is shown

### Requirement: Rejected key during use
When any API request answers `401`, the dashboard SHALL remove the stored key, clear cached data and show the sign-in page with a message that the key is no longer accepted, so a revoked key never leaves the operator on a broken page.

#### Scenario: Key revoked while browsing
- **WHEN** a signed-in operator's key is revoked and the next request answers `401`
- **THEN** the sign-in page is shown with a message that the key is no longer accepted, and the key is no longer stored
