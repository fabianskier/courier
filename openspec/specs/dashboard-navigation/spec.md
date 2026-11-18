# dashboard-navigation Specification

## Purpose
Gives the signed-in dashboard a sidebar layout with grouped navigation, the key in use and a merchant switcher that focuses the lists on one merchant.

## Requirements

### Requirement: Sidebar layout
Signed-in pages, the overview included, SHALL use a sidebar with links, each with an icon and a text label, to Overview and, grouped, to Events, Deliveries and Failed ("Activity") and Endpoints and Merchants ("Configuration"), marking the current page; the key's name, its scopes and a "Sign out" action at its bottom; and a header with a toggle that collapses the sidebar to icons, a breadcrumb naming the current page, and the live status. Pages without a stored key MUST NOT show the sidebar.

#### Scenario: Sidebar on a data page
- **WHEN** a signed-in operator opens the deliveries page
- **THEN** the sidebar shows the six pages in their groups with Deliveries marked as current, the key's name and scopes and "Sign out", and the header's breadcrumb names Deliveries

#### Scenario: Sidebar collapses
- **WHEN** the operator uses the sidebar toggle
- **THEN** the sidebar collapses to icons, and using the toggle again expands it

#### Scenario: No sidebar without a key
- **WHEN** an operator without a key opens the overview or the sign-in page
- **THEN** no sidebar is shown

### Requirement: Merchant switcher
The sidebar SHALL have a switcher at its top listing "All merchants" and every merchant. The selection MUST be kept for the browser session and applied as the `merchant_id` filter of the Events, Deliveries, Failed and Endpoints lists: the sidebar links carry it, and choosing a merchant while on one of those lists applies it there. "All merchants" MUST remove the filter. The switcher only filters views and MUST NOT change what the key may access.

#### Scenario: Merchant chosen
- **WHEN** the operator on the deliveries page chooses "Harbor Outfitters" in the switcher
- **THEN** the deliveries list is requested with Harbor's `merchant_id`, and the sidebar's Events, Deliveries, Failed and Endpoints links carry it

#### Scenario: Selection kept
- **WHEN** the operator has chosen a merchant and reloads the page
- **THEN** the switcher still shows that merchant

#### Scenario: All merchants
- **WHEN** the operator chooses "All merchants"
- **THEN** the lists are requested without `merchant_id` and the links carry no merchant
