# Spec Delta

## Purpose

Keeps the merchants whose events courier delivers: who they are, whether they are active, and the API operators use to manage them.

## ADDED Requirements

### Requirement: Create merchants
The system SHALL create a merchant from a name of 1 to 255 characters (surrounding whitespace removed). A new merchant MUST be enabled and get a generated id. Names need not be unique.

#### Scenario: Merchant created
- **WHEN** an operator with `write` scope sends `POST /api/v1/merchants` with name "Acme Shop"
- **THEN** the response is `201` with the merchant's id, name "Acme Shop", `enabled: true` and its creation time

#### Scenario: Invalid name
- **WHEN** an operator sends `POST /api/v1/merchants` with an empty or missing name
- **THEN** the response is `422` with code `invalid` and an error on `name`, and no merchant is created

### Requirement: Show and list merchants
The system SHALL show one merchant by id and list merchants oldest first, with pagination. Requests for an unknown or malformed id MUST get `404` with code `not_found`.

#### Scenario: Show a merchant
- **WHEN** an operator with `read` scope sends `GET /api/v1/merchants/:id` for an existing merchant
- **THEN** the response is `200` with that merchant

#### Scenario: Unknown merchant
- **WHEN** an operator requests `GET /api/v1/merchants/:id` with an id that does not exist or is not a valid id
- **THEN** the response is `404` with code `not_found`

#### Scenario: List merchants
- **WHEN** an operator with `read` scope sends `GET /api/v1/merchants` after creating three merchants
- **THEN** the response lists the three merchants oldest first

### Requirement: Update and disable merchants
The system SHALL let an operator change a merchant's name and its enabled flag. Merchants are never deleted. Disabling a merchant MUST NOT change its endpoints' own settings.

#### Scenario: Rename a merchant
- **WHEN** an operator with `write` scope sends `PATCH /api/v1/merchants/:id` with name "Acme Store"
- **THEN** the response is `200` and the merchant's name is "Acme Store"

#### Scenario: Disable a merchant
- **WHEN** an operator sends `PATCH /api/v1/merchants/:id` with `enabled: false`
- **THEN** the merchant is disabled and its endpoints keep their own enabled flags

### Requirement: Merchant API scopes
The system SHALL require the `read` scope to list and show merchants and the `write` scope to create and update them.

#### Scenario: Read-only key cannot create
- **WHEN** a key with only `read` sends `POST /api/v1/merchants`
- **THEN** the response is `403` with code `forbidden` and no merchant is created

#### Scenario: Write-only key cannot list
- **WHEN** a key with only `write` sends `GET /api/v1/merchants`
- **THEN** the response is `403` with code `forbidden`

### Requirement: Paginated lists
The system SHALL paginate list endpoints with a `limit` (default 50, maximum 100) and an opaque `cursor`. A response MUST include the items and a `next_cursor` that is `null` on the last page. An invalid `limit` or `cursor` MUST get `422` with code `invalid`.

#### Scenario: Two pages
- **WHEN** five merchants exist and an operator requests `limit=2`, then follows `next_cursor` until it is `null`
- **THEN** the pages return 2, 2 and 1 merchants, oldest first, with no repeats

#### Scenario: Invalid pagination
- **WHEN** an operator requests `limit=0`, `limit=101` or a cursor that was not issued by the system
- **THEN** the response is `422` with code `invalid`
