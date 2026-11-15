---
name: react-shadcn
description: Project conventions for the React frontend: TypeScript, feature folders, TanStack Query, forms, accessibility and tests. Use with the official shadcn skill when building or changing UI components, pages, forms, API clients or frontend tests.
---

# React frontend conventions

How to use shadcn/ui itself (CLI, components, registries, theming) is covered by the **official `shadcn` skill**. Follow it for that. This skill only holds the conventions of this project.

Follow the accepted ADRs for the build tool, router and real-time transport. If an ADR does not cover something, propose one instead of guessing.

## Stack and ownership

- React with TypeScript in `strict` mode; no `any` without a comment explaining why.
- shadcn/ui components are source code we own (under `src/components/ui/`). Add them through the CLI as the shadcn skill describes, and keep edits to generated components small.
- Theme through shadcn's CSS variables, not hard-coded colors.

## Structure

- Organize by feature: `src/features/<feature>/` with its components, hooks and API calls. Shared code goes in `src/components/` and `src/lib/`.
- Keep components small and mostly presentational; put data fetching in hooks.

## Data and forms

- Server state (anything from the API) goes through TanStack Query: query keys are built in one place; mutations invalidate the queries they affect.
- Type the API client from the backend's OpenAPI document, so types do not drift.
- Forms use React Hook Form with Zod schemas and the shadcn `Form` components. Validate on the client for UX; the server is the source of truth.
- Show loading, empty and error states for every data view.

## UX and accessibility

- Use semantic HTML and the accessible primitives shadcn builds on. Every interactive element is reachable by keyboard and has a label.
- Do not rely on color alone to show status; add text or an icon.
- Show dates and durations in the user's locale; store and send UTC.

## Tests

- Vitest and Testing Library; test behavior (what the user sees and does), not implementation details.
- Name tests after the spec: `describe("Requirement: <name>")` and `it("Scenario: <name>")`.
- Mock the network at the boundary (for example with MSW), not individual hooks.
- Run lint, type-check and tests before finishing; they must pass.
