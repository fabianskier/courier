# Design

## Context

See proposal.md. What exists:

- `src/routes/__root.tsx`: a header with `<nav aria-label="Main">` (a "Courier" link) and `<main>`; `src/routes/_app.tsx`: the guard, a `<nav aria-label="Dashboard">` with the page links, the "Key in use" label with the key's name and scope badges, the "Sign out" button and `LiveStatus` (`role="status"`); `src/routes/index.tsx`: the overview outside `_app` ("Sign in" link without a key, a "Dashboard pages" list of five links with a key).
- List pages read `merchant_id` from their Zod-validated URL search: `/events`, `/deliveries`, `/failed`, `/endpoints`. Merchants come from the cached lookup (`useMerchants`, `queryKeys.merchants`).
- Installed for this change: shadcn `sidebar` (+ `sheet`, `use-mobile` rewritten with `useSyncExternalStore`), `breadcrumb`, `collapsible`, `avatar`; `dropdown-menu`, `separator`, `tooltip` already existed.
- Protected tests use: navigation "Main" and heading "Overview" without a key; the "Dashboard pages" list; navigation "Dashboard" with the page links; "Key in use"; the "Sign out" button (clicked directly, not inside a menu); the live `status`.

## Goals / Non-Goals

**Goals:** the `sidebar-07` structure with courier's pages; one shell for `_app` pages and the signed-in overview; every name the protected tests use kept and visible without opening a menu.

**Non-Goals:** mobile-specific layouts beyond shadcn's sheet, keyboard shortcuts other than shadcn's default (Ctrl/Cmd+B), per-merchant access.

## Decisions

**Shell.** `AppShell({ title, children })` = `SidebarProvider` → `AppSidebar` + `SidebarInset` with a header (`SidebarTrigger` with `aria-label="Toggle sidebar"`, a `Separator`, a `Breadcrumb` "Dashboard / <title>", `LiveStatus` on the right) and the page. `_app.tsx` renders `<AppShell title={…}>` around its `Outlet` (title from the matched route: Overview, Events, Deliveries, Failed, Endpoints, Merchants, or the parent page for detail routes) and keeps the guard. The overview renders `AppShell` itself when a key is stored, after loading `/me` like `_app` (a `beforeLoad` that only runs when a key is stored, so the keyless overview still sends no request). The root layout hides its header when the shell is shown (the shell renders the only navigation).

**Sidebar parts** (following the block's files): `MerchantSwitcher` (block: `team-switcher`) as a `DropdownMenu` in `SidebarHeader`; `NavMain` with a plain Overview item and two `Collapsible` groups, open by default, inside `<nav aria-label="Dashboard">`, using `SidebarMenuButton asChild` with router `Link`s and `isActive` from the current route; `NavKey` (block: `nav-user`) in `SidebarFooter`: an `Avatar` with the key name's initials, the name with `aria-label="Key in use"`, scope badges, and a visible "Sign out" button (not inside a dropdown). Icons from lucide: `LayoutDashboard`, `Inbox`, `Send`, `CircleX`, `Webhook`, `Store`. `collapsible="icon"` on the `Sidebar`.

**Merchant context.** `src/lib/merchant-context.ts` keeps the selection in `sessionStorage` (`courier.merchant`, a merchant id or absent) behind `useSyncExternalStore`, so every part re-renders on change. Sidebar links for the four lists pass `search: { merchant_id }` when one is selected. Choosing in the switcher while on one of those lists also navigates to the same route with the new `merchant_id` (keeping its other filters); "All merchants" removes the key and the param. Detail pages, Merchants and the overview ignore it. The id is not a secret.

**Tests.** `tests/app-shell.test.tsx` (sidebar scenarios; the toggle checked through the sidebar's `data-state` of `expanded`/`collapsed`) and `tests/merchant-switcher.test.tsx` (switcher scenarios, with MSW answering `/merchants` and recording list requests). `matchMedia` is already stubbed (desktop), so the sidebar renders expanded, not as a sheet.

## Risks / Trade-offs

- [The switcher looks like access control] → its label says "Viewing" and the spec says it only filters; real per-merchant access would need user accounts (a later ADR).
- [Two headers during render] → the root header is hidden whenever the shell renders; tests for keyless and signed-in overview cover both.
