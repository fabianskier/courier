import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeAll, beforeEach, describe, expect, it } from 'vitest'
import type { EndpointDetail, MerchantDetail } from '@/lib/api/types'
import { formatDateTime } from '@/lib/format'
import { degradedEndpointFixture, endpointDetailFixture } from './support/endpoint-fixtures'
import { pageOf } from './support/event-fixtures'
import { errorFixture } from './support/fixtures'
import { merchantDetailFixture } from './support/merchant-fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()

// An in-memory read-only endpoints API: the list filtered by `merchant_id`
// and `degraded`, one endpoint, and the merchants lookup. Records the search
// of every endpoints list request.
function serveEndpoints(merchants: MerchantDetail[], endpoints: EndpointDetail[]) {
  const listSearches: URLSearchParams[] = []
  server.use(
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf(merchants))),
    http.get('*/api/v1/endpoints', ({ request }) => {
      const search = new URL(request.url).searchParams
      listSearches.push(search)
      const merchantId = search.get('merchant_id')
      const degraded = search.get('degraded')
      const found = endpoints.filter(
        (e) =>
          (!merchantId || e.merchant_id === merchantId) &&
          (degraded === null || String(e.degraded) === degraded),
      )
      return HttpResponse.json(pageOf(found))
    }),
    http.get('*/api/v1/endpoints/:id', ({ params }) => {
      const found = endpoints.find((e) => e.id === params.id)
      return found
        ? HttpResponse.json({ data: found })
        : HttpResponse.json(errorFixture('not_found', 'Not found.'), { status: 404 })
    }),
  )
  // The list's requests, not the lookup's (`limit=100`).
  return () => listSearches.filter((s) => !s.has('limit'))
}

const rowsOf = async () =>
  within(await screen.findByRole('table'))
    .getAllByRole('row')
    .slice(1)

const acme = merchantDetailFixture({ name: 'Acme' })
const harbor = merchantDetailFixture({ name: 'Harbor' })

// Radix Select uses pointer capture and scrolling, which jsdom lacks.
const stubs = { hasPointerCapture: () => false, scrollIntoView: () => {} }
beforeAll(() => void Object.assign(Element.prototype, stubs))

beforeEach(() => signIn(['read']))

describe('Requirement: Endpoints list', () => {
  it('Scenario: Endpoints listed', async () => {
    const healthy = endpointDetailFixture({ url: 'https://acme.test/hooks', merchant_id: acme.id })
    const failing = degradedEndpointFixture(7, {
      url: 'https://harbor.test/hooks',
      merchant_id: harbor.id,
      enabled: false,
    })
    serveEndpoints([acme, harbor], [healthy, failing])
    renderDashboard('/endpoints')

    const nav = await screen.findByRole('navigation', { name: 'Dashboard' })
    expect(within(nav).getByRole('link', { name: 'Endpoints' })).toHaveAttribute(
      'href',
      '/endpoints',
    )

    const rows = await rowsOf()
    expect(rows).toHaveLength(2)

    const first = within(rows[0])
    expect(first.getByRole('link', { name: healthy.url })).toHaveAttribute(
      'href',
      `/endpoints/${healthy.id}`,
    )
    expect(await first.findByText('Acme')).toBeInTheDocument()
    expect(first.getByText('Enabled')).toBeInTheDocument()
    expect(first.getByText('Healthy')).toBeInTheDocument()

    const second = within(rows[1])
    expect(second.getByRole('link', { name: failing.url })).toHaveAttribute(
      'href',
      `/endpoints/${failing.id}`,
    )
    expect(second.getByText('Harbor')).toBeInTheDocument()
    expect(second.getByText('Disabled')).toBeInTheDocument()
    expect(second.getByText('Degraded')).toBeInTheDocument()
    expect(second.getByText('7 consecutive failures')).toBeInTheDocument()
  })

  it('Scenario: Degraded endpoints only', async () => {
    const healthy = endpointDetailFixture({ merchant_id: acme.id })
    const failingA = degradedEndpointFixture(23, { merchant_id: acme.id })
    const failingB = degradedEndpointFixture(5, { merchant_id: harbor.id })
    const listSearches = serveEndpoints([acme, harbor], [healthy, failingA, failingB])
    const { router } = renderDashboard('/endpoints')

    expect(await rowsOf()).toHaveLength(3)
    await userEvent.click(screen.getByRole('checkbox', { name: 'Degraded only' }))

    await waitFor(() => expect(router.state.location.search).toEqual({ degraded: true }))
    expect(router.state.location.href).toContain('degraded=true')
    await waitFor(() => expect(screen.queryByText(healthy.url)).not.toBeInTheDocument())
    expect(listSearches().at(-1)?.get('degraded')).toBe('true')

    const rows = await rowsOf()
    expect(rows).toHaveLength(2)
    expect(within(rows[0]).getByText('Degraded')).toBeInTheDocument()
    expect(within(rows[0]).getByText('23 consecutive failures')).toBeInTheDocument()
    expect(within(rows[1]).getByText('Degraded')).toBeInTheDocument()
    expect(within(rows[1]).getByText('5 consecutive failures')).toBeInTheDocument()
  })

  it('Scenario: Endpoints of one merchant', async () => {
    const acmeHook = endpointDetailFixture({ url: 'https://acme.test/a', merchant_id: acme.id })
    const harborHook = endpointDetailFixture({
      url: 'https://harbor.test/a',
      merchant_id: harbor.id,
    })
    const listSearches = serveEndpoints([acme, harbor], [acmeHook, harborHook])
    const { router } = renderDashboard('/endpoints')

    expect(await rowsOf()).toHaveLength(2)
    await userEvent.click(screen.getByLabelText('Merchant'))
    await userEvent.click(await screen.findByRole('option', { name: 'Harbor' }))

    await waitFor(() => expect(screen.queryByText(acmeHook.url)).not.toBeInTheDocument())
    expect(router.state.location.search).toEqual({ merchant_id: harbor.id })
    expect(listSearches().at(-1)?.get('merchant_id')).toBe(harbor.id)
    const rows = await rowsOf()
    expect(rows).toHaveLength(1)
    expect(within(rows[0]).getByRole('link', { name: harborHook.url })).toBeInTheDocument()
  })

  it('reads the filters from the URL', async () => {
    const failing = degradedEndpointFixture(3, { merchant_id: acme.id })
    const listSearches = serveEndpoints([acme], [failing])
    renderDashboard(`/endpoints?merchant_id=${acme.id}&degraded=true`)

    expect(await rowsOf()).toHaveLength(1)
    const search = listSearches()[0]
    expect(search.get('merchant_id')).toBe(acme.id)
    expect(search.get('degraded')).toBe('true')
    expect(screen.getByRole('checkbox', { name: 'Degraded only' })).toBeChecked()
  })
})

describe('Requirement: Endpoint page', () => {
  it('Scenario: Endpoint details', async () => {
    const endpoint = endpointDetailFixture({
      url: 'https://acme.test/hooks',
      merchant_id: acme.id,
      description: 'Order updates',
      event_types: ['payment.*', 'refund.created'],
      retry_window_seconds: 5_400,
      retry_on_4xx: true,
      max_concurrency: 4,
    })
    serveEndpoints([acme], [endpoint])
    renderDashboard(`/endpoints/${endpoint.id}`)

    expect(await screen.findByRole('heading', { name: endpoint.url })).toBeInTheDocument()
    expect(await screen.findByRole('link', { name: 'Acme' })).toHaveAttribute(
      'href',
      `/merchants/${acme.id}`,
    )
    expect(screen.getByText('Order updates')).toBeInTheDocument()
    const filters = screen.getByRole('list', { name: 'Event types' })
    expect(within(filters).getByText('payment.*')).toBeInTheDocument()
    expect(within(filters).getByText('refund.created')).toBeInTheDocument()
    expect(screen.getByText('Enabled')).toBeInTheDocument()
    expect(screen.getByText('1.5 hours')).toBeInTheDocument()
    expect(screen.getByText('Yes')).toBeInTheDocument()
    expect(screen.getByText('4')).toBeInTheDocument()
    expect(screen.getByText('Healthy')).toBeInTheDocument()

    const deliveries = screen.getByRole('link', { name: 'Deliveries of this endpoint' })
    expect(deliveries).toHaveAttribute('href', `/deliveries?endpoint_id=${endpoint.id}`)
  })

  it('shows "All event types" without filters and when the previous secret stops signing', async () => {
    const endpoint = endpointDetailFixture({
      previous_secret_expires_at: '2026-11-18T12:00:00Z',
    })
    serveEndpoints([acme], [endpoint])
    renderDashboard(`/endpoints/${endpoint.id}`)

    expect(await screen.findByText('All event types')).toBeInTheDocument()
    expect(screen.getByText('24 hours')).toBeInTheDocument()
    expect(
      screen.getByText(`Signs until ${formatDateTime('2026-11-18T12:00:00Z')}`),
    ).toBeInTheDocument()
  })

  it('Scenario: Degraded endpoint details', async () => {
    const endpoint = degradedEndpointFixture(23, { merchant_id: acme.id })
    serveEndpoints([acme], [endpoint])
    renderDashboard(`/endpoints/${endpoint.id}`)

    expect(await screen.findByText('Degraded')).toBeInTheDocument()
    expect(screen.getByText('Degraded since')).toBeInTheDocument()
    expect(screen.getByText(formatDateTime(endpoint.degraded_at))).toBeInTheDocument()
    expect(screen.getByText('23 consecutive failures')).toBeInTheDocument()
  })

  it('Scenario: Unknown endpoint', async () => {
    serveEndpoints([], [])
    renderDashboard('/endpoints/missing')

    expect(await screen.findByRole('heading', { name: 'Endpoint not found' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to the endpoints' })).toHaveAttribute(
      'href',
      '/endpoints',
    )
  })

  it('links each endpoint on the merchant page to its endpoint page', async () => {
    const endpoint = endpointDetailFixture({ merchant_id: acme.id })
    serveEndpoints([acme], [endpoint])
    server.use(http.get('*/api/v1/merchants/:id', () => HttpResponse.json({ data: acme })))
    renderDashboard(`/merchants/${acme.id}`)

    const list = await screen.findByRole('list', { name: 'Endpoints' })
    expect(within(list).getByRole('link', { name: endpoint.url })).toHaveAttribute(
      'href',
      `/endpoints/${endpoint.id}`,
    )
  })
})
