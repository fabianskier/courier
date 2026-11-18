# Design

## Context

See proposal.md. `frontend/src/index.css` holds shadcn's variables for `:root` and `.dark` (neutral greys, `--primary` near black, `--chart-1..5` greys, `--sidebar-*`), and `@theme inline` maps them to Tailwind colors. `Badge` (`src/components/ui/badge.tsx`) has `cva` variants and renders `data-variant`. `StatusBadge` (`features/deliveries/status-badge.tsx`), `HealthBadge` (`features/endpoints/health-badge.tsx`) and `LiveStatus` (`components/live-status.tsx`) pick variants. `next-themes` is installed (Sonner already calls `useTheme`). There are two headers: the root one for keyless pages (`nav` "Main") and the `AppShell` header (toggle, breadcrumb, live status). Tests stub `matchMedia` to `matches: false`.

## Goals / Non-Goals

**Goals:** one place for every color (the CSS variables); WCAG AA contrast for text on `primary`, `success`, `warning` and `destructive` in both modes; no flash of the wrong mode.

**Non-Goals:** changing radius, fonts or density; theming per merchant.

## Decisions

**Palette (Tailwind v4 values, OKLCH).** Light / dark:

| Token | Light | Dark |
|---|---|---|
| `--primary` | indigo-600 `oklch(0.511 0.262 276.966)` | indigo-400 `oklch(0.673 0.182 276.935)` |
| `--primary-foreground` | `oklch(0.985 0 0)` | indigo-950 `oklch(0.257 0.09 281.288)` |
| `--ring`, `--sidebar-ring` | as `--primary` | as `--primary` |
| `--sidebar-primary` / `-foreground` | as `--primary` / `-foreground` | as `--primary` / `-foreground` |
| `--accent`, `--sidebar-accent` | indigo-50 `oklch(0.962 0.018 272.314)` | indigo-950 `oklch(0.257 0.09 281.288)` |
| `--accent-foreground`, `--sidebar-accent-foreground` | indigo-700 `oklch(0.457 0.24 277.023)` | indigo-200 `oklch(0.87 0.065 274.039)` |
| `--destructive` | rose-600 `oklch(0.586 0.253 17.585)` | rose-400 `oklch(0.712 0.194 13.428)` |
| `--success` (new) | emerald-600 `oklch(0.596 0.145 163.225)` | emerald-400 `oklch(0.765 0.177 163.223)` |
| `--success-foreground` (new) | `oklch(0.985 0 0)` | emerald-950 `oklch(0.262 0.051 172.552)` |
| `--warning` (new) | amber-500 `oklch(0.769 0.188 70.08)` | amber-400 `oklch(0.828 0.189 84.429)` |
| `--warning-foreground` (new) | amber-950 `oklch(0.279 0.077 45.635)` | amber-950 `oklch(0.279 0.077 45.635)` |
| `--chart-1..5` | indigo-500, emerald-500, rose-500, amber-500, zinc-400 | indigo-400, emerald-400, rose-400, amber-400, zinc-500 |

The remaining greys (`--background`, `--foreground`, `--card`, `--popover`, `--secondary`, `--muted`, `--border`, `--input`, `--sidebar`, `--sidebar-border` and their foregrounds) move from neutral to the matching Tailwind `zinc` shades (same lightness steps, zinc's slight blue hue). `@theme inline` gains `--color-success`, `--color-success-foreground`, `--color-warning`, `--color-warning-foreground`.

**Badge variants.** `badge.tsx` gains `success` and `warning` variants built like `destructive` (a tinted background with the token as text, e.g. `bg-success/10 text-success` with the dark equivalents through the tokens, never raw palette classes). `StatusBadge`: succeeded→`success`, failed→`destructive`, pending→`warning`, skipped→`secondary`. `HealthBadge`: Healthy→`success`, Degraded→`destructive`. `LiveStatus`: live→`success` dot or badge, reconnecting→`warning`.

**Mode.** `ThemeProvider` from `next-themes` wraps the app in `main.tsx` with `attribute="class"`, `defaultTheme="system"`, `enableSystem`, `storageKey="courier.theme"`, `disableTransitionOnChange`. `ModeToggle` (`src/components/mode-toggle.tsx`): a `DropdownMenu` with a ghost icon `Button` (`Sun`/`Moon` icons, `aria-label="Theme"`) and items Light, Dark, System, rendered in the root header and in the `AppShell` header. An inline script in `index.html`'s `<head>` reads `courier.theme` (or `prefers-color-scheme`) and adds `dark` to `<html>` before the bundle loads.

**Tests.** `frontend/tests/theme-colors.test.tsx` and `theme-mode.test.tsx`: status and health badge variants via `data-variant`; choosing Dark adds `dark` to `document.documentElement` and stores `courier.theme`; with no stored choice and a `matchMedia` stub answering dark, the root is dark. The no-flash scenario is covered by a test that runs the `index.html` head script on a bare document with `courier.theme = "dark"` and checks the class.

## Risks / Trade-offs

- [Contrast of amber with white text] → warning uses dark text (`--warning-foreground` amber-950) in both modes.
- [The inline script and `next-themes` disagree] → both read the same storage key and fall back to the same media query.
