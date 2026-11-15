# How courier is built

courier is developed with a spec-driven, agent-assisted workflow. Requirements and decisions are written first; code is then written by AI agents one small task at a time, checked by deterministic rules, and merged only after a human approves it.

## Smelt

**Smelt** is the author's own software factory: a private, personal tool written in Elixir/OTP. It is not open source and is not needed to build, run or test courier; it only changes *how* the code gets written.

### What it does

For each task of an [OpenSpec](https://github.com/Fission-AI/OpenSpec) change (`openspec/changes/<change>/tasks.md`), `mix smelt.task REPO CHANGE TASK_ID`:

1. creates a fresh **git worktree** for the task, outside the project;
2. runs **Claude Code headless** in it with limited permissions and only the project's own settings and skills (no API key: the Claude Code CLI only);
3. runs a **deterministic gate**, with no AI involved:
   - existing tests (and Smelt's own files) must not be changed,
   - the diff must stay small (about 400 lines and 20 files per task),
   - `openspec validate --strict` must pass,
   - the project's `.smelt/checks.sh` (compile with warnings as errors, format, tests) must pass within a timeout;
4. if the gate fails, gives the agent **one retry** with the failure details;
5. asks the **human to approve** the merge, or discards the work.

### Where it fits in this project

| Phase | How it is done |
|---|---|
| Analysis, architecture, ADRs (`docs/`) | Written with Claude Code interactively, reviewed and accepted by the author |
| Bootstraps (Phoenix, Vite, shadcn scaffolding) | By hand: generated code is too large for the gate, and the gate needs `.smelt/checks.sh` in the base commit |
| OpenSpec changes (proposal, design, specs, tasks) | Written with Claude Code interactively, approved by the author |
| Each task of a change | **Smelt** (`mix smelt.task`) |
| Merge | Approved by the author |

Every task merged through Smelt passed the same checks that CI runs, and every spec scenario has a test named after it (`describe "Requirement: …"`, `test "Scenario: …"`).

### Status (2026-11)

Smelt is young and growing alongside this project. Today it covers **one task end to end from the command line**:

- Done: Claude Code runner with a streamed event log, one worktree per task, the deterministic gate, the task pipeline (build → gate → one retry → approval → merge or discard), and agent isolation from the user's own Claude Code setup.
- Not yet: resuming runs after a crash or usage limit, running several tasks in parallel with a merge queue, writing proposals and specs as part of the pipeline, automatic review, and a web dashboard (built but parked).

This section is updated as Smelt gains features that change how courier is built.
