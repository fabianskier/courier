# Spec Delta

## Purpose

Controls who can call courier's API and what each caller may do, using named API keys with scopes that operators create, list and revoke.

## ADDED Requirements

### Requirement: Create API keys
The system SHALL create an API key from a name and a non-empty set of scopes, each one of `ingest`, `read` or `write`. It MUST return the plaintext token once, at creation, and store only a hash of it. Names MUST be unique.

#### Scenario: Key created with scopes
- **WHEN** an operator creates a key named "dashboard" with scopes `read` and `write`
- **THEN** the system returns a token and a key named "dashboard" with exactly those scopes

#### Scenario: Token is not stored in plaintext
- **WHEN** a key is created
- **THEN** the stored key record does not contain the plaintext token

#### Scenario: Duplicate name rejected
- **WHEN** an operator creates a key with the name of an existing key
- **THEN** creation fails with an error on the name and no key is added

#### Scenario: Invalid scopes rejected
- **WHEN** an operator creates a key with no scopes or with an unknown scope such as `admin`
- **THEN** creation fails with an error on the scopes and no key is added

### Requirement: Tokens are unguessable and distinct
The system SHALL generate each token from at least 32 bytes of cryptographically secure randomness, with the fixed prefix `ck_` so tokens can be recognized in leaks. Two keys MUST never share a token.

#### Scenario: Token format
- **WHEN** a key is created
- **THEN** its token starts with `ck_` and carries at least 32 bytes of random data

#### Scenario: Tokens differ
- **WHEN** two keys are created
- **THEN** their tokens are different

### Requirement: List API keys
The system SHALL list all keys with their name, scopes, creation time and revocation time, and MUST NOT include tokens or token hashes in the listing.

#### Scenario: Listing shows keys without secrets
- **WHEN** an operator lists keys after creating one active and one revoked key
- **THEN** both keys appear with name, scopes and revocation status, and no token or hash is shown

### Requirement: Revoke API keys
The system SHALL revoke a key by name. A revoked key MUST stop authenticating immediately and MUST remain in the listing. Revoking an unknown name MUST fail with a not-found error.

#### Scenario: Revoked key no longer authenticates
- **WHEN** an operator revokes a key and a request then uses its token
- **THEN** the request is rejected as unauthenticated

#### Scenario: Unknown key
- **WHEN** an operator revokes a name that does not exist
- **THEN** the system reports that the key was not found

### Requirement: Authenticate API requests
The system SHALL authenticate requests to `/api/v1` with the header `Authorization: Bearer <token>`. A missing header, a malformed header, an unknown token or a revoked key MUST get `401` with error code `unauthorized` and a `www-authenticate: Bearer` header.

#### Scenario: Valid token
- **WHEN** a request to `GET /api/v1/me` carries the token of an active key
- **THEN** the response is `200`

#### Scenario: Missing token
- **WHEN** a request to `GET /api/v1/me` has no `Authorization` header
- **THEN** the response is `401` with error code `unauthorized` and a `www-authenticate: Bearer` header

#### Scenario: Unknown token
- **WHEN** a request to `GET /api/v1/me` carries a token that matches no key
- **THEN** the response is `401` with error code `unauthorized`

#### Scenario: Malformed header
- **WHEN** a request to `GET /api/v1/me` sends `Authorization: Basic abc` or `Bearer` with no token
- **THEN** the response is `401` with error code `unauthorized`

### Requirement: Authorize by scope
The system SHALL let each protected route declare the scope it requires. A request authenticated with a key that lacks that scope MUST get `403` with error code `forbidden`. Scopes are independent: `write` does not imply `read`.

#### Scenario: Key with the required scope
- **WHEN** a route requires `read` and the key has `read`
- **THEN** the request is processed

#### Scenario: Key without the required scope
- **WHEN** a route requires `write` and the key has only `read`
- **THEN** the response is `403` with error code `forbidden`

### Requirement: Identify the calling key
The system SHALL answer `GET /api/v1/me` for any active key, whatever its scopes, with the key's name and scopes as JSON.

#### Scenario: Who am I
- **WHEN** the key "dashboard" with scopes `read` and `write` calls `GET /api/v1/me`
- **THEN** the response is `200` with `{"name": "dashboard", "scopes": ["read", "write"]}`

### Requirement: Consistent API error shape
The system SHALL return API errors from `/api/v1` as JSON of the form `{"error": {"code": "<code>", "message": "<text>"}}`.

#### Scenario: Error body
- **WHEN** a request to `/api/v1/me` is rejected as unauthenticated
- **THEN** the body is `{"error": {"code": "unauthorized", "message": ...}}` with a non-empty message

### Requirement: Tokens never leak
The system MUST NOT write plaintext tokens to logs, and token values MUST NOT appear in error responses.

#### Scenario: Rejected token not echoed
- **WHEN** a request with an unknown token is rejected
- **THEN** neither the response body nor the captured log output contains that token

### Requirement: Manage keys from the command line
The system SHALL provide command-line tasks to create a key (printing its token once, with a warning that it cannot be shown again), list keys, and revoke a key by name. Invalid input MUST print the errors and exit with a non-zero status.

#### Scenario: Create from the command line
- **WHEN** an operator runs the create task with name "producer" and scope `ingest`
- **THEN** the output contains the new token and the key exists with scope `ingest`

#### Scenario: Invalid input from the command line
- **WHEN** an operator runs the create task with an unknown scope
- **THEN** the task prints the error and exits with a non-zero status

#### Scenario: List and revoke from the command line
- **WHEN** an operator revokes "producer" with the revoke task and then runs the list task
- **THEN** the listing shows "producer" as revoked and does not show any token
