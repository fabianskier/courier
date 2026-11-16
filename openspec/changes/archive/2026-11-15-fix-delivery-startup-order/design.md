# Design

## Context

Children of `Courier.Supervisor` (`:one_for_one`) start in list order and stop in reverse order. Today: Telemetry, Vault, Repo, Oban, QueueManager, Finch, TaskSupervisor, DNSCluster, PubSub, Endpoint.

## Goals / Non-Goals

**Goals:** no delivery job runs before, or keeps running after, the HTTP pool and the request supervisor.

**Non-Goals:** reordering unrelated children.

## Decisions

- New order: Telemetry, Vault, Repo, Finch, TaskSupervisor, Oban, QueueManager, DNSCluster, PubSub, Endpoint. The comments move with their children.
- Test: `Supervisor.which_children(Courier.Supervisor)` lists children in reverse start order; reverse it and assert that the index of `Courier.Finch` and of `Courier.Delivery.TaskSupervisor` is lower than the index of Oban, and Oban's is lower than `Courier.Delivery.QueueManager`'s. Oban's child id is `Oban` (its `child_spec/1` uses the instance name).

## Risks / Trade-offs

- [None worth noting] → Finch and the task supervisor do not depend on Oban or the Repo.

## Migration Plan

Code only.
