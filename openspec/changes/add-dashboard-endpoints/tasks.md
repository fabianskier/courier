# Tasks

Each task must stay within the gate's diff budget (about 800 changed lines and 20 files, tests included; the route tree is not counted). Existing files under `frontend/tests/` are protected: put new tests and helpers in new files. Read design.md before each task. Frontend tests are named after the spec (`describe("Requirement: …")`, `it("Scenario: …")`) and mock the network with MSW.

## 1. Merchants

- [x] 1.1 Add `PATCH` and JSON bodies to `apiFetch` and `details` to `ApiError`, the `applyApiErrors` form helper, the merchants list (`_app/merchants.index`), the create form, the merchant page (`_app/merchants.$merchantId`) with rename and disable/enable, the "Merchants" navigation link and the write-scope rule for these pages; verify with `frontend/tests/merchants.test.tsx` covering every scenario of "Merchants list and page" and "Create and edit merchants" (the merchant page's endpoints list may show URLs only until 2.1 adds endpoint pages)

## 2. Endpoints

- [x] 2.1 Add `HealthBadge`, the endpoints list (`_app/endpoints.index` with merchant and "degraded only" filters in the URL), the endpoint page (`_app/endpoints.$endpointId`, read-only: details, health, secret overlap, link to its deliveries), the "Endpoints" navigation link, and links from the merchant page; verify with `frontend/tests/endpoints.test.tsx` covering every scenario of "Endpoints list" and "Endpoint page"
- [ ] 2.2 Add the create form (`_app/endpoints.new`, merchant preselected from the search, "New endpoint" on the merchant page) and `SecretReveal`; verify with `frontend/tests/endpoint-create.test.tsx` covering every scenario of "Create endpoints" and "Secret shown once"
- [ ] 2.3 Add editing, disable/enable and secret rotation on the endpoint page, and the write-scope rule for every endpoint action; verify with `frontend/tests/endpoint-edit.test.tsx` covering every scenario of "Edit, disable and rotate endpoints" and "Management needs the write scope"

## 3. Docs

- [ ] 3.1 Update `docs/architecture.md` ("Dashboard SPA": the merchants and endpoints routes, forms and secrets shown once), add a README step to the local demo (open "Endpoints", turn on "degraded only", open `harbor-fail`, rotate its secret; note that dashboard-created endpoints are not registered with the demo receiver), and mark step 11 done in `docs/roadmap.md` with step 12 next; verify `sh .smelt/checks.sh` and `openspec validate add-dashboard-endpoints --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-dashboard-endpoints <task> --model opus` (3.1 with `--model sonnet`) and review before merging; merge each task before starting the next.
- After the last merge, run the Docker demo, create a merchant and an endpoint, rotate a secret, then archive the change.
