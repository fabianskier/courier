# Tasks

Each task must stay within the gate's diff budget (about 800 changed lines and 20 files, tests included; the route tree is not counted). Existing test files are protected: put new tests in new files and keep the accessible names listed in design.md. Read design.md before each task. Frontend tests are named after the spec (`describe("Requirement: …")`, `it("Scenario: …")`).

## 1. Sidebar

- [x] 1.1 Add `AppShell` and `AppSidebar` (`NavMain` with the two collapsible groups, `NavKey` with the key and "Sign out"), the header with the toggle, breadcrumb and live status, use the shell in the `_app` layout and in the signed-in overview, and hide the root header when the shell renders; verify with `frontend/tests/app-shell.test.tsx` covering every scenario of "Sidebar layout", and that every existing frontend test still passes
- [ ] 1.2 Add `MerchantSwitcher` and `src/lib/merchant-context.ts`, and carry the selected merchant in the sidebar's list links and on the current list page; verify with `frontend/tests/merchant-switcher.test.tsx` covering every scenario of "Merchant switcher"

## 2. Docs

- [ ] 2.1 Update `docs/architecture.md` ("Dashboard SPA": the shell, sidebar parts and merchant switcher) and the README's dashboard step (the sidebar and the switcher), and add the change to `docs/roadmap.md`; verify `sh .smelt/checks.sh` and `openspec validate add-sidebar-layout --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build 1.1 and 1.2 with `mix smelt.task ~/code/courier add-sidebar-layout <task> --model opus` and 2.1 with `--model sonnet`; review and merge each before the next.
- After the last merge, check the layout in the Docker demo, then archive the change.
