# Proposal

## Why

The dashboard uses shadcn's default greyscale theme: buttons, the active page and statuses all look grey (only "failed" is red), and there is no dark mode although the stylesheet already defines dark colors. A colored theme makes the active state and the statuses readable at a glance, and a dark mode is expected of an operator dashboard.

## What Changes

- **Theme**: indigo as the primary color (buttons, links, focus ring, the active sidebar item, the merchant switcher) on a cool `zinc` grey base, in light and dark variants.
- **Status colors**: semantic `success` (emerald) and `warning` (amber) tokens next to `destructive` (rose), each with light and dark values; delivery statuses (`succeeded`, `failed`, `pending`, `skipped`), endpoint health (`Healthy`, `Degraded`) and the live status use them. Icons and text stay, so status never depends on color alone.
- **Dark mode**: a Light / Dark / System selector in the header of every page (signed in or not), remembered in the browser, following the operating system by default and applied before the first paint (no light flash).
- **Not in this change**: a different shadcn style (radius, density, font stay as `radix-nova`), per-merchant branding, a high-contrast theme.

## Capabilities

### New Capabilities
- `dashboard-theme`: the color theme, the status colors and the light/dark mode.

### Modified Capabilities
None.

## Impact

- Frontend only: `src/index.css` (variables), `badge.tsx` gains `success` and `warning` variants, `StatusBadge`, `HealthBadge` and `LiveStatus` use them; a `ThemeProvider` (`next-themes`, already installed) in `main.tsx`, a `ModeToggle` in both headers, and an inline script in `index.html` to set the class before paint. Tests in new files.
- No new dependencies, no backend changes. Existing tests are not modified.
