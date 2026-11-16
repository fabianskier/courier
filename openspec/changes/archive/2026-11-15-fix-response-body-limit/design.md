# Design

## Context

`Courier.Delivery.Client.post/3` calls `Req.post/1` with `decode_body: false` and truncates `response.body` to 4096 bytes in `sanitize_body/1`. Timeouts: 5 s connect (on the `Courier.Finch` pool) and 15 s `receive_timeout`, which applies to each read, not to the whole response. Accepted ADR that applies: "Oban with one queue per endpoint …" (a slow endpoint must only use its own share of resources).

## Goals / Non-Goals

**Goals:** memory per attempt bounded by about 4 KB of body; time per attempt bounded by a fixed deadline.

**Non-Goals:** changing what is stored, the retry rules or the worker.

## Decisions

### Streaming with a byte limit

Req's `into:` option with a function: on each `{:data, chunk}` it appends to `resp.body` up to 4096 bytes in total and returns `{:halt, {req, resp}}` once the limit is reached, otherwise `{:cont, {req, resp}}`. The response then carries at most 4096 bytes, and `sanitize_body/1` keeps working unchanged. Halting stops reading and Finch closes the connection, so it is not reused. Alternative: `into: :self` with manual `Req.parse_message/2`; rejected as more code for the same result.

### Total deadline

`post/4` runs the request in a `Task` under a `Task.Supervisor` (`Courier.Delivery.TaskSupervisor`, started in `Courier.Application`) and waits with `Task.yield(task, deadline) || Task.shutdown(task, :brutal_kill)`; no result → `{:error, "timeout"}`. Deadline: 30 000 ms, overridable with the `:deadline` option. 30 s is larger than connect (5 s) plus a normal receive (15 s), so the deadline only cuts slow-drip responses. Alternative: Finch's `request_timeout`; rejected because it is not exposed through Req's options in a documented way and the task approach is easy to test.

### Options

`post(url, body, headers, opts \\ [])`: `opts` are merged last, over the defaults and the application config. `:deadline` is taken out before calling Req. When `opts` contains `plug: nil`, the `:plug` key is removed from the merged options, so a test reaches a real server through Finch instead of the `Req.Test` stub configured in `config/test.exs`; the moduledoc documents this.

### Tests

New file `test/courier/delivery/client_streaming_test.exs`, `async: false`, starting Bandit with `start_supervised!({Bandit, plug: ..., port: 0, ip: :loopback})` and reading the port with `ThousandIsland.listener_info/1`. Plugs:

- large: `send_chunked` then 2,560 chunks of 4 KB (10 MB), recording in an `Agent` how many chunks were sent before `chunk/2` returned `{:error, :closed}`;
- drip: `send_chunked`, one byte, then `Process.sleep` longer than the test's deadline (e.g. deadline 300 ms, sleep 2 s).

## Risks / Trade-offs

- [Halting closes the connection, so a large-body endpoint gets no keep-alive] → Acceptable: such responses are abnormal.
- [A receiver that does its work slowly before answering (over 30 s) now always times out] → Already the case with the 15 s receive timeout for the first byte; documented.

## Migration Plan

Code only; nothing to migrate.
