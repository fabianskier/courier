# Proposal

## Why

An end-to-end check of `add-merchants-endpoints` found endpoint signing secrets (`whsec_…`) in plaintext in the development server log. Ecto logs every query at `debug` level with its parameters as cast, before `Cloak` encrypts them, so each `INSERT` of an endpoint and each `UPDATE` from a rotation printed the new (and the previous) secret. Production logs at `info` and is not affected by default, but turning on `debug` during an incident would leak every secret written meanwhile, and the project rule is that secrets are never logged.

## What Changes

- Database writes that carry an endpoint's `secret` or `previous_secret` (creating an endpoint and rotating its secret) are no longer logged by Ecto.
- A test captures logs at `debug` level while creating an endpoint and rotating its secret over HTTP and asserts that neither secret appears.
- `docs/architecture.md` states the rule for any future write of a secret.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `webhook-endpoints`: adds a requirement that signing secrets never appear in logs, at any log level.

## Impact

- `Courier.Endpoints.create_endpoint/1` and `rotate_secret/2` (repo calls only); no API or data changes.
- One new test file. No new dependencies.
