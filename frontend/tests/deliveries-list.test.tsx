import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest'
import { formatDateTime } from '@/lib/format'
import { deliveryFixture } from './support/delivery-fixtures'
import { endpointFixture, merchantFixture, pageOf } from './support/event-fixtures'
import { errorFixture } from './support/fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()
const [acme, globex] = [merchantFixture('Acme'), merchantFixture('Globex')]
const [hookA, hookB] = [endpointFixture('https://acme.test/a'), endpointFixture('https://b.test')]

// Radix Select uses pointer capture and scrolling, which jsdom lacks.
const stubs = { hasPointerCapture: () => false, scrollIntoView: () => {} }
beforeAll(() => void Object.assign(Element.prototype, stubs))

let asked: URL[] = []
beforeEach(() => {
  asked = []
  server.events.on('request:start', ({ request }) => {
    const url = new URL(request.url)
    if (url.pathname.startsWith('/api/v1/deliveries')) asked.push(url)
  })
  signIn()
  server.use(
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([acme, globex]))),
    http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([hookA, hookB]))),
  )
})
afterEach(() => server.events.removeAllListeners())

const answerDeliveries = (answer: (url: URL) => object) =>
  server.use(
    http.get('*/api/v1/deliveries', ({ request }) =>
      HttpResponse.json(answer(new URL(request.url))),
    ),
  )
const deliveryLink = (id: string) => screen.findByRole('link', { name: id.slice(0, 8) })

const pick = async (user: ReturnType<typeof userEvent.setup>, label: string, option: string) => {
  await user.click(screen.getByLabelText(label))
  await user.click(await screen.findByRole('option', { name: option }))
}

describe('Requirement: Deliveries list', () => {
  it('Scenario: Deliveries listed', async () => {
    const newest = deliveryFixture({
      endpoint_id: hookA.id,
      status: 'failed',
      attempt_count: 3,
      inserted_at: '2026-11-02T08:00:00Z',
    })
    const older = deliveryFixture({ endpoint_id: hookB.id, event_type: 'refund.created' })
    answerDeliveries(() => pageOf([newest, older]))
    renderDashboard('/deliveries')

    expect(await deliveryLink(newest.id)).toHaveAttribute('href', `/deliveries/${newest.id}`)
    expect(await deliveryLink(older.id)).toHaveAttribute('href', `/deliveries/${older.id}`)
    const [, first, second] = screen.getAllByRole('row')
    expect(await within(first!).findByText(hookA.url)).toBeInTheDocument()
    expect(first).toHaveTextContent(
      `${formatDateTime(newest.inserted_at)}failedpayment.succeeded${hookA.url}3`,
    )
    expect(second).toHaveTextContent(`succeededrefund.created${hookB.url}1`)
    // The status is text next to an icon, not a color alone.
    expect(within(first!).getByText('failed').querySelector('svg')).not.toBeNull()
  })

  it('Scenario: Delivery filters combined', async () => {
    const match = deliveryFixture({ status: 'failed', endpoint_id: hookA.id })
    answerDeliveries((url) => pageOf(url.searchParams.has('status') ? [match] : []))
    const user = userEvent.setup()
    const { router } = renderDashboard('/deliveries')
    await screen.findByText('No deliveries match.')

    await pick(user, 'Status', 'failed')
    await pick(user, 'Merchant', 'Acme')
    await pick(user, 'Endpoint', hookA.url)
    await user.type(screen.getByLabelText('Event type'), 'payment.succeeded')
    await user.click(screen.getByRole('button', { name: 'Apply' }))

    const expected = {
      status: 'failed',
      merchant_id: acme.id,
      endpoint_id: hookA.id,
      event_type: 'payment.succeeded',
    }
    await waitFor(() => expect(router.state.location.search).toEqual(expected))
    await deliveryLink(match.id)
    expect(Object.fromEntries(asked.at(-1)!.searchParams)).toEqual(expected)
  })

  it('Scenario: Load more deliveries', async () => {
    const firstPage = [deliveryFixture(), deliveryFixture()]
    const secondPage = [deliveryFixture()]
    answerDeliveries((url) =>
      url.searchParams.get('cursor') === 'c2' ? pageOf(secondPage) : pageOf(firstPage, 'c2'),
    )
    renderDashboard('/deliveries')

    await userEvent.click(await screen.findByRole('button', { name: 'Load more' }))

    await deliveryLink(secondPage[0]!.id)
    expect(asked.at(-1)!.searchParams.get('cursor')).toBe('c2')
    const hrefs = screen.getAllByRole('link', { name: /^d/ }).map((a) => a.getAttribute('href'))
    expect(hrefs).toEqual([...firstPage, ...secondPage].map((d) => `/deliveries/${d.id}`))
    expect(screen.queryByRole('button', { name: 'Load more' })).not.toBeInTheDocument()
  })

  // Not a scenario of its own: the requirement asks for the events list's states.
  it('shows an error with a retry when deliveries fail to load', async () => {
    const failure = HttpResponse.json(errorFixture('internal', 'Boom.'), { status: 500 })
    server.use(http.get('*/api/v1/deliveries', () => failure))
    renderDashboard('/deliveries')

    expect(await screen.findByText('Deliveries could not be loaded.')).toBeInTheDocument()
    const delivery = deliveryFixture()
    answerDeliveries(() => pageOf([delivery]))
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))

    await deliveryLink(delivery.id)
    expect(asked).toHaveLength(2)
  })
})

describe('Requirement: Failed deliveries view', () => {
  it('Scenario: Only failed deliveries', async () => {
    const failed = [deliveryFixture({ status: 'failed' }), deliveryFixture({ status: 'failed' })]
    answerDeliveries((url) => pageOf(url.searchParams.get('status') === 'failed' ? failed : []))
    renderDashboard('/deliveries')

    const nav = await screen.findByRole('navigation', { name: 'Dashboard' })
    await screen.findByText('No deliveries match.')
    asked = []
    await userEvent.click(within(nav).getByRole('link', { name: 'Failed' }))

    for (const delivery of failed) await deliveryLink(delivery.id)
    expect(asked.map((url) => url.searchParams.get('status'))).toEqual(['failed'])
    const rows = screen.getAllByRole('row').slice(1)
    for (const row of rows) expect(row).toHaveTextContent('failed')
    expect(screen.queryByLabelText('Status')).not.toBeInTheDocument()
  })

  it('Scenario: No failed deliveries', async () => {
    answerDeliveries(() => pageOf([]))
    renderDashboard('/failed')

    expect(await screen.findByText('No deliveries have failed.')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(asked[0]!.searchParams.get('status')).toBe('failed')
  })
})
