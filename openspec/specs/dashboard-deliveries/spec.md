# dashboard-deliveries Specification

## Purpose
Lets an operator see in the dashboard what came in and what was delivered: events and deliveries with filters, each delivery's attempt timeline and resend links, the failed deliveries, and a confirmed resend for keys allowed to write.

## Requirements

### Requirement: Events list
The dashboard SHALL list events newest first with their received time, type, merchant name and id, filtered by merchant, exact type and a time range, and load further pages with a "Load more" action that follows the API cursor. The filters MUST be kept in the page URL, so a filtered list can be reloaded and shared. Times MUST be shown in the operator's locale and sent to the API in UTC. The list MUST show distinct loading, empty and error states; the error state MUST offer a retry.

#### Scenario: Events listed
- **WHEN** a signed-in operator opens the events page
- **THEN** the newest events are shown with their received time, type and merchant name, each linking to its event page

#### Scenario: Event filters kept in the URL
- **WHEN** an operator picks a merchant, types `payment.succeeded` and sets a start time, then reloads the page
- **THEN** the URL holds the three filters, the API is asked with `merchant_id`, `type` and `since`, and the same filtered list is shown after the reload

#### Scenario: Load more events
- **WHEN** the first page of events has a `next_cursor` and the operator chooses "Load more"
- **THEN** the next page is requested with that cursor and appended below the first, and the action disappears when `next_cursor` is null

#### Scenario: No events
- **WHEN** the API returns an empty list
- **THEN** the page says that no events match, instead of an empty table

#### Scenario: Events failed to load
- **WHEN** the events request fails with a server error
- **THEN** the page shows an error message with a retry action, and retrying requests the list again

### Requirement: Event page
The dashboard SHALL show an event's id, type, merchant, occurred and received times, its payload as formatted JSON text, and its deliveries with their status and endpoint, each linking to the delivery page. The payload MUST be rendered as text, never interpreted as HTML. An unknown event MUST show a not-found message.

#### Scenario: Event with deliveries
- **WHEN** an operator opens an event with two deliveries
- **THEN** the page shows the event's fields, the formatted payload and both deliveries with their status, each linking to its delivery page

#### Scenario: Payload shown as text
- **WHEN** an event's payload contains the string `<img src=x onerror=alert(1)>`
- **THEN** the page shows that string as text and no image element is created

#### Scenario: Unknown event
- **WHEN** an operator opens an event id that the API answers with `404`
- **THEN** the page says the event was not found, with a link back to the events list

### Requirement: Deliveries list
The dashboard SHALL list deliveries newest first with their creation time, status, event type, endpoint URL and attempt count, filtered by status, merchant, endpoint, exact event type and a time range, with "Load more" pagination, filters kept in the URL, times in the operator's locale, and loading, empty and error states as in the events list. A delivery's status MUST be shown as text (with an icon), not by color alone.

#### Scenario: Deliveries listed
- **WHEN** a signed-in operator opens the deliveries page
- **THEN** the newest deliveries are shown with creation time, status as text, event type, endpoint URL and attempt count, each linking to its delivery page

#### Scenario: Delivery filters combined
- **WHEN** an operator picks status `failed`, a merchant, an endpoint and event type `payment.succeeded`
- **THEN** the URL holds the four filters and the API is asked with `status`, `merchant_id`, `endpoint_id` and `event_type` together

#### Scenario: Load more deliveries
- **WHEN** the first page of deliveries has a `next_cursor` and the operator chooses "Load more"
- **THEN** the next page is requested with that cursor and appended below the first

### Requirement: Failed deliveries view
The dashboard SHALL have a "Failed" view, linked from the main navigation, that lists only failed deliveries, newest first, with the other filters of the deliveries list except status. When there are none, it MUST say so.

#### Scenario: Only failed deliveries
- **WHEN** an operator opens the failed view
- **THEN** the API is asked with `status=failed` and only failed deliveries are shown

#### Scenario: No failed deliveries
- **WHEN** the API returns no failed deliveries
- **THEN** the view says that no deliveries have failed

### Requirement: Delivery page
The dashboard SHALL show a delivery's status, event (type and link), endpoint URL, creation and completion times, window end and the actor that created it. A pending delivery MUST show its next attempt time; a skipped delivery MUST say that the endpoint's event filter excluded the event. An unknown delivery MUST show a not-found message.

#### Scenario: Pending delivery
- **WHEN** an operator opens a pending delivery with a next attempt time
- **THEN** the page shows that the delivery is pending and when the next attempt is due

#### Scenario: Skipped delivery
- **WHEN** an operator opens a skipped delivery
- **THEN** the page says the endpoint's event filter excluded the event, and shows no timeline

#### Scenario: Unknown delivery
- **WHEN** an operator opens a delivery id that the API answers with `404`
- **THEN** the page says the delivery was not found, with a link back to the deliveries list

### Requirement: Attempt timeline
The delivery page SHALL show the delivery's attempts in order as a timeline: number, start time, duration, response status code or error, and the response body as text, shortened with a "Show more" action when longer than 500 characters.

#### Scenario: Failed then succeeded
- **WHEN** an operator opens a delivery whose first attempt got `500` and second `200`
- **THEN** the timeline shows attempt 1 with `500` and attempt 2 with `200`, each with its time and duration, and the status `succeeded`

#### Scenario: Attempt without a response
- **WHEN** an attempt has no status code and the error `timeout`
- **THEN** its timeline entry shows the error `timeout` instead of a status code

#### Scenario: Long response body shortened
- **WHEN** an attempt's response body has 2,000 characters
- **THEN** the entry shows its first 500 characters and a "Show more" action that reveals the rest

### Requirement: Resend links
The dashboard SHALL link a resend to the delivery it resends, and list a delivery's resends (status, actor, creation time) with a link to each.

#### Scenario: Delivery and its resend linked
- **WHEN** an operator opens a delivery that was resent, and then the resend
- **THEN** the first page lists the resend with its actor and a link to it, and the second page links back to the resent delivery

### Requirement: Resend with confirmation
The dashboard's resend action SHALL open a confirmation dialog naming the endpoint URL before anything is sent. On confirmation it MUST call `POST /api/v1/deliveries/:id/resend`, then open the new delivery and confirm that it was created; on cancel nothing is sent. When the API refuses the resend (`409` or `422`), the dashboard MUST show the API's message and stay on the delivery.

#### Scenario: Resend confirmed
- **WHEN** an operator with a `write` key resends a failed delivery and confirms
- **THEN** `POST /api/v1/deliveries/:id/resend` is called once, and the new delivery's page is shown with a confirmation message

#### Scenario: Resend cancelled
- **WHEN** an operator opens the resend dialog and cancels
- **THEN** no request is sent and the dialog closes

#### Scenario: Resend refused
- **WHEN** an operator confirms a resend and the API answers `422` with code `endpoint_disabled`
- **THEN** the API's message is shown, and the operator stays on the delivery

### Requirement: Resend only when allowed
The dashboard SHALL offer the resend action only on terminal deliveries (`succeeded` or `failed`). When the signed-in key lacks the `write` scope, the action MUST be shown disabled with an explanation. A pending or skipped delivery MUST NOT offer it.

#### Scenario: Read-only key
- **WHEN** an operator whose key has only the `read` scope opens a failed delivery
- **THEN** the resend action is disabled and explains that resending needs the `write` scope

#### Scenario: No resend while pending
- **WHEN** an operator opens a pending delivery
- **THEN** no resend action is offered
