# Proposal

## Why

The dashboard's navigation is a row of links in the page header, and after signing in the overview shows no navigation at all. As the dashboard grew to six pages (overview, events, deliveries, failed, endpoints, merchants), a sidebar in the style of shadcn's `sidebar-07` block gives a clearer structure, collapses to icons to leave room for tables, and its top-left switcher lets the operator focus the lists on one merchant.

## What Changes

- **Sidebar layout** for every signed-in page, the overview included: a collapsible sidebar (to icons) with the merchant switcher at the top, the pages in two groups ("Activity": Events, Deliveries, Failed; "Configuration": Endpoints, Merchants) plus Overview, and the key in use with "Sign out" at the bottom; a header with the sidebar toggle, a breadcrumb of the current page and the live status. Pages without a key keep the current simple header.
- **Merchant switcher**: lists "All merchants" and the merchants; picking one keeps it for the browser session and applies it as the `merchant_id` filter of the Events, Deliveries, Failed and Endpoints lists (through the sidebar links and on the current list page). "All merchants" removes it. It is a view filter only; it grants or restricts nothing.
- **Components**: shadcn `sidebar`, `sheet`, `breadcrumb`, `collapsible` and `avatar`, installed before the tasks.
- **Not in this change**: user accounts or per-merchant access (an API key still sees every merchant), metrics on the overview, new API endpoints.

## Capabilities

### New Capabilities
- `dashboard-navigation`: the sidebar layout and the merchant switcher.

### Modified Capabilities
None. Sign-in, the data pages and live updates keep their specified behaviour.

## Impact

- Frontend only: `src/components/app-shell.tsx`, `src/components/app-sidebar.tsx` (with nav, merchant switcher and key footer parts), the `_app` layout and the signed-in overview use the shell; a small `src/lib/merchant-context.ts`. Tests in new files.
- No backend changes. Existing tests are not modified, and the accessible names they use are kept.
