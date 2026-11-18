# Tasks

Each task must stay within the gate's diff budget (about 800 changed lines and 20 files, tests included). Existing test files are protected: put new tests in new files and keep the accessible names existing tests use. Read design.md before each task. Frontend tests are named after the spec (`describe("Requirement: …")`, `it("Scenario: …")`).

## 1. Theme

- [ ] 1.1 Apply the palette in `src/index.css` (light and dark, zinc greys, the new `success` and `warning` tokens and their `@theme inline` colors), add the `success` and `warning` variants to `badge.tsx`, and use them in `StatusBadge`, `HealthBadge` and `LiveStatus` as in design.md; verify with `frontend/tests/theme-colors.test.tsx` covering every scenario of "Status colors"
- [ ] 1.2 Add the `ThemeProvider`, `ModeToggle` in both headers and the `index.html` head script; document the theme and the mode selector in `docs/architecture.md` ("Dashboard SPA") and the README's dashboard step, and add the change to `docs/roadmap.md`; verify with `frontend/tests/theme-mode.test.tsx` covering every scenario of "Light and dark mode", and that `sh .smelt/checks.sh` and `openspec validate add-theme-and-dark-mode --strict` pass

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-theme-and-dark-mode <task> --model opus`; review and merge each before the next.
- After the last merge, look at the dashboard in both modes in the Docker demo, then archive the change.
