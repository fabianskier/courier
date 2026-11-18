# Spec Delta

## Purpose

Gives the dashboard a colored theme with consistent status colors and a light or dark mode the operator chooses.

## ADDED Requirements

### Requirement: Status colors
The dashboard SHALL show delivery statuses and endpoint health with semantic colors as well as an icon and text: `succeeded` and "Healthy" as success (emerald), `failed` and "Degraded" as destructive (rose), `pending` as warning (amber) and `skipped` as neutral (grey). The live status MUST use success when live and warning while reconnecting.

#### Scenario: Delivery status colors
- **WHEN** a list shows deliveries with the statuses `succeeded`, `failed`, `pending` and `skipped`
- **THEN** their badges use the `success`, `destructive`, `warning` and neutral variants, each with its icon and status text

#### Scenario: Endpoint health colors
- **WHEN** the endpoints list shows a healthy and a degraded endpoint
- **THEN** "Healthy" uses the `success` variant and "Degraded" the `destructive` variant

### Requirement: Light and dark mode
Every page SHALL offer a Light / Dark / System selector in its header. The choice MUST be remembered in the browser; without a choice the dashboard MUST follow the operating system's preference. The chosen mode MUST apply before the first paint, so a dark page never flashes light.

#### Scenario: Dark chosen
- **WHEN** the operator chooses Dark
- **THEN** the page's root element has the `dark` class and the choice is stored in the browser

#### Scenario: Choice remembered
- **WHEN** the operator chose Dark and opens the dashboard again
- **THEN** the page starts dark without showing light first

#### Scenario: System by default
- **WHEN** the operator never chose a mode and the operating system prefers dark
- **THEN** the dashboard is dark, and switching the system preference to light makes it light
