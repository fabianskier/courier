# Tasks

## 1. Stop logging secret writes

- [ ] 1.1 Pass `log: false` to the `Repo.insert` in `Courier.Endpoints.create_endpoint/1` and the `Repo.update` in `Courier.Endpoints.rotate_secret/2`, with a short comment on why, and add the rule ("any repo call that writes a secret column passes `log: false`") to the "Security notes" of `docs/architecture.md`; verify with a new test file `test/courier_web/controllers/endpoint_secret_logging_test.exs` (`describe "Requirement: Signing secrets never appear in logs"`) with tests named "Scenario: Creating an endpoint logs no secret" and "Scenario: Rotating a secret logs no secret", which raise the test process's log level to `:debug` (`Logger.put_process_level/2`), capture logs with `ExUnit.CaptureLog.with_log(level: :debug, ...)` around the HTTP requests, assert the captured log is not empty (so the capture works) and that it contains neither the full secrets nor their base64 parts; check that both tests fail without the `log: false` change before keeping it; and verify `mix precommit` and `sh .smelt/checks.sh` pass

## Workflow follow-up

- Archive the change after merge (`openspec archive fix-secret-logging`) and re-run the end-to-end check of the server log.
