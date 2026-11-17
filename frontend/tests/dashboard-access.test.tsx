import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { apiFetch } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
import { errorFixture, meFixture } from './support/fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn, TEST_KEY } from './support/session'

const server = setupApiServer()

let requests: Request[] = []
const record = ({ request }: { request: Request }) => {
  requests.push(request.clone())
}

beforeEach(() => {
  requests = []
  server.events.on('request:start', record)
})

afterEach(() => {
  server.events.removeAllListeners()
})

function answerMe(check: (request: Request) => Response) {
  server.use(http.get('*/api/v1/me', ({ request }) => check(request)))
}

const unauthorized = () =>
  HttpResponse.json(errorFixture('unauthorized', 'Invalid API key.'), { status: 401 })

async function submitKey(key: string) {
  const user = userEvent.setup()
  await user.type(await screen.findByLabelText('API key'), key)
  await user.click(screen.getByRole('button', { name: 'Sign in' }))
}

describe('Requirement: Data pages need a key', () => {
  it('Scenario: Overview without a key', async () => {
    renderDashboard('/')

    expect(await screen.findByRole('heading', { name: 'Overview' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Sign in' })).toHaveAttribute('href', '/sign-in')
    expect(requests).toHaveLength(0)
  })

  it('Scenario: Valid key accepted', async () => {
    answerMe((request) =>
      request.headers.get('Authorization') === `Bearer ${TEST_KEY}`
        ? HttpResponse.json(meFixture())
        : unauthorized(),
    )
    const { router } = renderDashboard('/deliveries')

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    await submitKey(TEST_KEY)

    expect(await screen.findByRole('heading', { name: 'Deliveries' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/deliveries')
    expect(requests.map((r) => new URL(r.url).pathname)).toContain('/api/v1/me')
    expect(window.sessionStorage.getItem('courier.apiKey')).toBe(TEST_KEY)
  })
})

describe('Requirement: Sign in with an API key', () => {
  it('Scenario: Rejected key', async () => {
    answerMe(unauthorized)
    const { router } = renderDashboard('/sign-in')

    await submitKey('ck_wrong')

    expect(await screen.findByText('This key was not accepted.')).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/sign-in')
    expect(screen.queryByText(/no longer accepted/)).not.toBeInTheDocument()
    expect(window.sessionStorage.length).toBe(0)
  })

  it('Scenario: Courier unreachable', async () => {
    answerMe(() => HttpResponse.error())
    renderDashboard('/sign-in')

    await submitKey(TEST_KEY)
    expect(await screen.findByText('Courier could not be reached.')).toBeInTheDocument()
    expect(window.sessionStorage.length).toBe(0)

    answerMe(() => HttpResponse.json(errorFixture('internal', 'Boom.'), { status: 503 }))
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    await waitFor(() => expect(requests).toHaveLength(2))
    expect(await screen.findByText('Courier could not be reached.')).toBeInTheDocument()
    expect(window.sessionStorage.length).toBe(0)
  })
})

describe('Requirement: Key kept for the browser session only', () => {
  it('Scenario: Key survives a reload', async () => {
    signIn(['read'], 'ops-reader')
    renderDashboard('/deliveries')

    expect(await screen.findByRole('heading', { name: 'Deliveries' })).toBeInTheDocument()
    const keyInUse = screen.getByLabelText('Key in use')
    expect(keyInUse).toHaveTextContent('ops-reader')
    expect(keyInUse).toHaveTextContent('read')
    expect(screen.queryByLabelText('API key')).not.toBeInTheDocument()
    expect(requests[0]?.headers.get('Authorization')).toBe(`Bearer ${TEST_KEY}`)
  })

  it('Scenario: Key stays out of the URL and local storage', async () => {
    answerMe(() => HttpResponse.json(meFixture()))
    const { router } = renderDashboard('/deliveries')
    const visited = [router.state.location.href]

    await submitKey(TEST_KEY)
    expect(await screen.findByRole('heading', { name: 'Deliveries' })).toBeInTheDocument()
    visited.push(router.state.location.href)

    await userEvent.click(screen.getByRole('link', { name: 'Overview' }))
    await userEvent.click(await screen.findByRole('link', { name: 'Open deliveries' }))
    expect(await screen.findByRole('heading', { name: 'Deliveries' })).toBeInTheDocument()
    visited.push(router.state.location.href)

    for (const href of visited) expect(href).not.toContain(TEST_KEY)
    for (const request of requests) expect(request.url).not.toContain(TEST_KEY)
    expect(window.localStorage.length).toBe(0)
    expect(document.cookie).not.toContain(TEST_KEY)
    expect(window.sessionStorage.getItem('courier.apiKey')).toBe(TEST_KEY)
  })
})

describe('Requirement: Sign out', () => {
  it('Scenario: Signed out', async () => {
    signIn()
    const { queryClient } = renderDashboard('/deliveries')

    await userEvent.click(await screen.findByRole('button', { name: 'Sign out' }))

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(window.sessionStorage.getItem('courier.apiKey')).toBeNull()
    expect(queryClient.getQueryData(queryKeys.me)).toBeUndefined()
    expect(queryClient.getQueryCache().getAll()).toHaveLength(0)
  })
})

describe('Requirement: Rejected key during use', () => {
  it('Scenario: Key revoked while browsing', async () => {
    signIn()
    const { router, queryClient } = renderDashboard('/deliveries')
    expect(await screen.findByRole('heading', { name: 'Deliveries' })).toBeInTheDocument()

    server.use(http.get('*/api/v1/deliveries', unauthorized))
    await act(() => apiFetch('/deliveries').catch(() => undefined))

    expect(await screen.findByText(/key is no longer accepted/)).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(router.state.location.search).toMatchObject({ redirect: '/deliveries' })
    expect(window.sessionStorage.getItem('courier.apiKey')).toBeNull()
    await waitFor(() => expect(queryClient.getQueryCache().getAll()).toHaveLength(0))
  })
})
