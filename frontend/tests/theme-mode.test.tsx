import { QueryClientProvider } from '@tanstack/react-query'
import { createMemoryHistory, RouterProvider } from '@tanstack/react-router'
import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import indexHtml from '../index.html?raw'
import { THEME_STORAGE_KEY, ThemeProvider } from '@/components/theme-provider'
import { createAppQueryClient, createAppRouter } from '@/router'
import { endpointFixture, merchantFixture, pageOf } from './support/event-fixtures'
import { setupApiServer } from './support/server'
import { signIn } from './support/session'

const server = setupApiServer()

// The operating system's color scheme, as `matchMedia` answers it.
let systemDark = false
const listeners = new Set<(event: MediaQueryListEvent) => void>()
const originalMatchMedia = window.matchMedia

const mediaQuery = (query: string): MediaQueryList =>
  ({
    get matches() {
      return query.includes('dark') && systemDark
    },
    media: query,
    onchange: null,
    addListener: (listener: (event: MediaQueryListEvent) => void) => listeners.add(listener),
    removeListener: (listener: (event: MediaQueryListEvent) => void) => listeners.delete(listener),
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }) as unknown as MediaQueryList

// Switches the system preference and tells the listeners, as the browser does.
function setSystemDark(dark: boolean) {
  systemDark = dark
  const event = { matches: dark, media: '(prefers-color-scheme: dark)' } as MediaQueryListEvent
  act(() => listeners.forEach((listener) => listener(event)))
}

const root = document.documentElement

beforeEach(() => {
  systemDark = false
  listeners.clear()
  window.matchMedia = mediaQuery
})

afterEach(() => {
  window.matchMedia = originalMatchMedia
  window.localStorage.clear()
  window.sessionStorage.clear()
  root.className = ''
  root.removeAttribute('style')
})

// The whole app at `path` inside the `ThemeProvider`, as `main.tsx` renders it.
function renderThemedApp(path: string) {
  const queryClient = createAppQueryClient()
  queryClient.setDefaultOptions({ queries: { retry: false } })
  const router = createAppRouter(queryClient, createMemoryHistory({ initialEntries: [path] }))
  return render(
    <ThemeProvider>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </ThemeProvider>,
  )
}

// Runs the inline script of `index.html`'s head, as the browser does before
// loading the bundle.
function runHeadScript() {
  const script = /<script id="theme-script">([\s\S]*?)<\/script>/.exec(indexHtml)
  if (!script) throw new Error('index.html has no theme script')
  new Function(script[1]!)()
}

async function chooseMode(mode: 'Light' | 'Dark' | 'System') {
  const user = userEvent.setup()
  await user.click(await screen.findByRole('button', { name: 'Theme' }))
  await user.click(await screen.findByRole('menuitemradio', { name: mode }))
}

describe('Requirement: Light and dark mode', () => {
  it('Scenario: Dark chosen', async () => {
    renderThemedApp('/sign-in')
    within(await screen.findByRole('navigation', { name: 'Main' })).getByRole('button', {
      name: 'Theme',
    })

    await chooseMode('Dark')

    expect(root).toHaveClass('dark')
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBe('dark')

    await chooseMode('Light')

    expect(root).not.toHaveClass('dark')
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBe('light')
  })

  it('offers the selector in the signed-in header too', async () => {
    signIn()
    const hook = endpointFixture('https://acme.test/hooks')
    server.use(
      http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([merchantFixture('Acme')]))),
      http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([hook]))),
    )
    renderThemedApp('/endpoints')

    const header = (await screen.findByRole('button', { name: 'Toggle sidebar' })).closest(
      'header',
    ) as HTMLElement
    within(header).getByRole('button', { name: 'Theme' })

    await chooseMode('Dark')

    expect(root).toHaveClass('dark')
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBe('dark')
  })

  it('Scenario: Choice remembered', async () => {
    window.localStorage.setItem(THEME_STORAGE_KEY, 'dark')

    // Before the bundle loads, so the first paint is already dark.
    runHeadScript()
    expect(root).toHaveClass('dark')

    renderThemedApp('/sign-in')
    expect(root).toHaveClass('dark')

    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: 'Theme' }))
    expect(await screen.findByRole('menuitemradio', { name: 'Dark' })).toHaveAttribute(
      'aria-checked',
      'true',
    )
  })

  it('starts light before the first paint when Light was chosen on a dark system', () => {
    systemDark = true
    window.localStorage.setItem(THEME_STORAGE_KEY, 'light')

    runHeadScript()

    expect(root).not.toHaveClass('dark')
  })

  it('Scenario: System by default', () => {
    systemDark = true

    runHeadScript()
    expect(root).toHaveClass('dark')

    renderThemedApp('/sign-in')
    expect(root).toHaveClass('dark')
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBeNull()

    setSystemDark(false)
    expect(root).not.toHaveClass('dark')

    setSystemDark(true)
    expect(root).toHaveClass('dark')
  })
})
