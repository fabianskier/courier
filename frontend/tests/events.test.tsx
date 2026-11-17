import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest'
import { formatDateTime } from '@/lib/format'
import { endpointFixture, eventFixture, merchantFixture, pageOf } from './support/event-fixtures'
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
    if (url.pathname.startsWith('/api/v1/events')) asked.push(url)
  })
  signIn()
  server.use(
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([acme, globex]))),
    http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([hookA, hookB]))),
  )
})
afterEach(() => server.events.removeAllListeners())

const answerEvents = (answer: (url: URL) => object) =>
  server.use(
    http.get('*/api/v1/events', ({ request }) => HttpResponse.json(answer(new URL(request.url)))),
  )
const answerEvent = (answer: () => Response) => server.use(http.get('*/api/v1/events/:id', answer))
const eventLink = (id: string) => screen.findByRole('link', { name: id.slice(0, 8) })

describe('Requirement: Events list', () => {
  it('Scenario: Events listed', async () => {
    const newest = eventFixture({ merchant_id: acme.id, received_at: '2026-11-02T08:00:00Z' })
    const older = eventFixture({ merchant_id: globex.id, type: 'refund.created' })
    answerEvents(() => pageOf([newest, older]))
    renderDashboard('/events')

    expect(await eventLink(newest.id)).toHaveAttribute('href', `/events/${newest.id}`)
    expect(await eventLink(older.id)).toHaveAttribute('href', `/events/${older.id}`)
    const [, first, second] = screen.getAllByRole('row')
    expect(await within(first!).findByText('Acme')).toBeInTheDocument()
    expect(first).toHaveTextContent(`${formatDateTime(newest.received_at)}payment.succeededAcme`)
    expect(second).toHaveTextContent('refund.createdGlobex')
  })

  it('Scenario: Event filters kept in the URL', async () => {
    const match = eventFixture({ merchant_id: acme.id })
    answerEvents((url) => pageOf(url.searchParams.has('merchant_id') ? [match] : []))
    const user = userEvent.setup()
    const first = renderDashboard('/events')
    await screen.findByText('No events match.')

    await user.click(screen.getByLabelText('Merchant'))
    await user.click(await screen.findByRole('option', { name: 'Acme' }))
    await user.type(screen.getByLabelText('Type'), 'payment.succeeded')
    fireEvent.change(screen.getByLabelText('Received from'), {
      target: { value: '2026-11-01T10:30' },
    })
    await user.click(screen.getByRole('button', { name: 'Apply' }))

    const since = new Date('2026-11-01T10:30').toISOString()
    const expected = { merchant_id: acme.id, type: 'payment.succeeded', since }
    await waitFor(() => expect(first.router.state.location.search).toEqual(expected))
    await eventLink(match.id)
    expect(Object.fromEntries(asked.at(-1)!.searchParams)).toEqual(expected)

    // A reload: a new app at the same URL asks for and shows the same list.
    const href = first.router.state.location.href
    first.unmount()
    asked = []
    renderDashboard(href)

    await eventLink(match.id)
    expect(Object.fromEntries(asked[0]!.searchParams)).toEqual(expected)
    expect(screen.getByLabelText('Received from')).toHaveValue('2026-11-01T10:30')
  })

  it('Scenario: Load more events', async () => {
    const firstPage = [eventFixture(), eventFixture()]
    const secondPage = [eventFixture()]
    answerEvents((url) =>
      url.searchParams.get('cursor') === 'c2' ? pageOf(secondPage) : pageOf(firstPage, 'c2'),
    )
    renderDashboard('/events')

    await userEvent.click(await screen.findByRole('button', { name: 'Load more' }))

    await eventLink(secondPage[0]!.id)
    expect(asked.at(-1)!.searchParams.get('cursor')).toBe('c2')
    const hrefs = screen.getAllByRole('link', { name: /^0/ }).map((a) => a.getAttribute('href'))
    expect(hrefs).toEqual([...firstPage, ...secondPage].map((e) => `/events/${e.id}`))
    expect(screen.queryByRole('button', { name: 'Load more' })).not.toBeInTheDocument()
  })

  it('Scenario: No events', async () => {
    answerEvents(() => pageOf([]))
    renderDashboard('/events')

    expect(await screen.findByText('No events match.')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('Scenario: Events failed to load', async () => {
    const failure = HttpResponse.json(errorFixture('internal', 'Boom.'), { status: 500 })
    server.use(http.get('*/api/v1/events', () => failure))
    renderDashboard('/events')

    expect(await screen.findByText('Events could not be loaded.')).toBeInTheDocument()
    const event = eventFixture()
    answerEvents(() => pageOf([event]))
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))

    await eventLink(event.id)
    expect(asked).toHaveLength(2)
  })
})

describe('Requirement: Event page', () => {
  it('Scenario: Event with deliveries', async () => {
    const deliveries = [
      { id: 'd1', endpoint_id: hookA.id, status: 'succeeded', url: hookA.url },
      { id: 'd2', endpoint_id: hookB.id, status: 'failed', url: hookB.url },
    ] as const
    const event = eventFixture({ merchant_id: acme.id, deliveries: [...deliveries] })
    answerEvent(() => HttpResponse.json({ data: event }))
    renderDashboard(`/events/${event.id}`)

    await screen.findByRole('heading', { name: 'Event payment.succeeded' })
    expect(await screen.findByText('Acme')).toBeInTheDocument()
    expect(screen.getByText(event.id)).toBeVisible()
    for (const time of [event.occurred_at, event.received_at]) {
      expect(screen.getByText(formatDateTime(time))).toBeVisible()
    }
    const payload = screen.getByLabelText('Payload').textContent
    expect(payload).toBe(JSON.stringify(event.payload, null, 2))

    const items = within(screen.getByRole('list', { name: 'Deliveries' })).getAllByRole('listitem')
    for (const [index, { id, status, url }] of deliveries.entries()) {
      expect(await within(items[index]!).findByText(url)).toBeVisible()
      expect(items[index]).toHaveTextContent(status)
      const link = within(items[index]!).getByRole('link', { name: `Delivery ${id}` })
      expect(link).toHaveAttribute('href', `/deliveries/${id}`)
    }
  })

  it('Scenario: Payload shown as text', async () => {
    const markup = '<img src=x onerror=alert(1)>'
    const event = eventFixture({ payload: { note: markup } })
    answerEvent(() => HttpResponse.json({ data: event }))
    const { container } = renderDashboard(`/events/${event.id}`)

    expect(await screen.findByLabelText('Payload')).toHaveTextContent(markup)
    expect(container.querySelector('img')).toBeNull()
  })

  it('Scenario: Unknown event', async () => {
    answerEvent(() => HttpResponse.json(errorFixture('not_found', 'Not found.'), { status: 404 }))
    renderDashboard(`/events/${eventFixture().id}`)

    expect(await screen.findByRole('heading', { name: 'Event not found' })).toBeInTheDocument()
    const back = screen.getByRole('link', { name: 'Back to the events' })
    expect(back).toHaveAttribute('href', '/events')
  })
})
