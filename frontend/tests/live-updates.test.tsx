import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import type { Socket } from 'phoenix'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { stopLive } from '@/lib/live/connection'
import {
  type LiveTransport,
  type NoticeHandler,
  type NoticeName,
  phoenixTransport,
  setTransportFactory,
} from '@/lib/live/transport'
import type { DeliveryDetail, DeliverySummary } from '@/lib/api/types'
import { attemptFixture, deliveryDetailFixture } from './support/delivery-detail-fixtures'
import { deliveryFixture } from './support/delivery-fixtures'
import { endpointFixture, merchantFixture, pageOf } from './support/event-fixtures'
import { errorFixture } from './support/fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn, TEST_KEY } from './support/session'

const server = setupApiServer()
const acme = merchantFixture('Acme')
const hook = endpointFixture('https://acme.test/hooks')

// A transport the test drives: it emits notices and status changes by hand.
class FakeTransport implements LiveTransport {
  readonly handlers = new Map<string, NoticeHandler>()
  private statusHandler: Parameters<LiveTransport['onStatus']>[0] = () => {}
  connected = false
  disconnected = false

  readonly token: string

  constructor(token: string) {
    this.token = token
  }

  connect() {
    this.connected = true
  }
  join(topic: string, onNotice: NoticeHandler) {
    this.handlers.set(topic, onNotice)
  }
  onStatus(handler: Parameters<LiveTransport['onStatus']>[0]) {
    this.statusHandler = handler
  }
  disconnect() {
    this.disconnected = true
  }

  notify(topic: string, name: NoticeName, payload: Record<string, unknown>) {
    act(() => this.handlers.get(topic)?.(name, payload))
  }
  status(status: 'live' | 'reconnecting') {
    act(() => this.statusHandler(status))
  }
}

let transports: FakeTransport[] = []
const transport = () => {
  const last = transports.at(-1)
  if (!last) throw new Error('no dashboard socket was opened')
  return last
}

// Paths of the API requests made, to count refetches.
let asked: string[] = []
const count = (path: string) => asked.filter((p) => p === path).length

beforeEach(() => {
  transports = []
  asked = []
  setTransportFactory((token) => {
    const fake = new FakeTransport(token)
    transports.push(fake)
    return fake
  })
  server.events.on('request:start', ({ request }) => {
    asked.push(new URL(request.url).pathname)
  })
  signIn()
  server.use(
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([acme]))),
    http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([hook]))),
  )
})
afterEach(() => {
  vi.useRealTimers()
  server.events.removeAllListeners()
  stopLive()
})

// Answers `GET /deliveries` with whatever `current()` holds at request time.
const serveDeliveryList = (current: () => DeliverySummary[]) =>
  server.use(http.get('*/api/v1/deliveries', () => HttpResponse.json(pageOf(current()))))

const serveDelivery = (current: () => DeliveryDetail) =>
  server.use(
    http.get('*/api/v1/deliveries/:id', ({ params }) =>
      params.id === current().id
        ? HttpResponse.json({ data: current() })
        : HttpResponse.json(errorFixture('not_found', 'Not found.'), { status: 404 }),
    ),
  )

const changed = (d: { id: string; event_id: string; endpoint_id: string; status: string }) => ({
  id: d.id,
  event_id: d.event_id,
  endpoint_id: d.endpoint_id,
  status: d.status,
})

describe('Requirement: Dashboard refreshes from notices', () => {
  it('Scenario: Failed delivery appears', async () => {
    let failed: DeliverySummary[] = []
    serveDeliveryList(() => failed)
    renderDashboard('/failed')

    expect(await screen.findByText('No deliveries have failed.')).toBeInTheDocument()
    expect(transport().token).toBe(TEST_KEY)
    expect([...transport().handlers.keys()]).toEqual([
      'dashboard:events',
      'dashboard:deliveries',
      'dashboard:endpoints',
      'dashboard:merchants',
    ])

    const delivery = deliveryFixture({ status: 'failed', endpoint_id: hook.id })
    failed = [delivery]
    const sent = Date.now()
    transport().notify('dashboard:deliveries', 'delivery_changed', changed(delivery))

    expect(
      await screen.findByRole('link', { name: delivery.id.slice(0, 8) }, { timeout: 5_000 }),
    ).toHaveAttribute('href', `/deliveries/${delivery.id}`)
    expect(Date.now() - sent).toBeLessThan(5_000)
  })

  it('Scenario: Open delivery refreshed', async () => {
    let delivery = deliveryDetailFixture({ status: 'pending', endpoint_id: hook.id, attempts: [] })
    serveDelivery(() => delivery)
    renderDashboard(`/deliveries/${delivery.id}`)

    expect(await screen.findByText('This delivery is pending.')).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: 'Attempts' })).not.toBeInTheDocument()

    delivery = {
      ...delivery,
      status: 'succeeded',
      attempt_count: 1,
      attempts: [attemptFixture({ response_status: 200 })],
    }
    transport().notify('dashboard:deliveries', 'delivery_changed', changed(delivery))

    expect(await screen.findByRole('list', { name: 'Attempts' })).toHaveTextContent('Attempt 1')
    expect(screen.getAllByText('succeeded').length).toBeGreaterThan(0)
  })

  it('Scenario: Burst coalesced', async () => {
    const delivery = deliveryFixture({ endpoint_id: hook.id })
    serveDeliveryList(() => [delivery])
    renderDashboard('/deliveries')
    await screen.findByRole('link', { name: delivery.id.slice(0, 8) })
    expect(count('/api/v1/deliveries')).toBe(1)

    vi.useFakeTimers()
    // 200 notices spread over one second, then time for every flush.
    for (let i = 0; i < 200; i++) {
      transport().notify('dashboard:deliveries', 'delivery_changed', changed(delivery))
      await vi.advanceTimersByTimeAsync(5)
    }
    await vi.advanceTimersByTimeAsync(3_000)
    vi.useRealTimers()

    await waitFor(() => expect(count('/api/v1/deliveries')).toBeGreaterThan(1))
    expect(count('/api/v1/deliveries') - 1).toBeLessThanOrEqual(2)
  })

  it('Scenario: Socket closed on sign-out', async () => {
    serveDeliveryList(() => [])
    const user = userEvent.setup()
    renderDashboard('/deliveries')
    await screen.findByRole('button', { name: 'Sign out' })

    const socket = transport()
    expect(socket.connected).toBe(true)
    await user.click(await screen.findByRole('button', { name: 'Sign out' }))

    expect(await screen.findByRole('heading', { name: /sign in/i })).toBeInTheDocument()
    expect(socket.disconnected).toBe(true)
  })
})

describe('Requirement: Reconnect and live status', () => {
  it('Scenario: Reconnect refetches', async () => {
    const delivery = deliveryFixture({ endpoint_id: hook.id })
    serveDeliveryList(() => [delivery])
    renderDashboard('/deliveries')
    await screen.findByRole('link', { name: delivery.id.slice(0, 8) })

    transport().status('live')
    expect(screen.getByRole('status')).toHaveTextContent('Live')
    const before = count('/api/v1/deliveries')

    transport().status('reconnecting')
    expect(screen.getByRole('status')).toHaveTextContent('Reconnecting…')
    expect(count('/api/v1/deliveries')).toBe(before)

    transport().status('live')
    expect(screen.getByRole('status')).toHaveTextContent('Live')
    await waitFor(() => expect(count('/api/v1/deliveries')).toBe(before + 1))
    // Every active query, the lookups included, and only once.
    expect(count('/api/v1/endpoints')).toBeGreaterThanOrEqual(2)
    await new Promise((resolve) => setTimeout(resolve, 300))
    expect(count('/api/v1/deliveries')).toBe(before + 1)
  })
})

describe('Dashboard socket', () => {
  it('closes the socket when a request answers 401', async () => {
    server.use(
      http.get('*/api/v1/deliveries', () =>
        HttpResponse.json(errorFixture('unauthorized', 'Invalid API key.'), { status: 401 }),
      ),
    )
    renderDashboard('/deliveries')

    await waitFor(() => expect(transport().disconnected).toBe(true))
  })

  it('sends the key as the auth token and forwards notices and status', () => {
    const channel = { on: vi.fn(), join: vi.fn() }
    const socket = {
      connect: vi.fn(),
      disconnect: vi.fn(),
      channel: vi.fn(() => channel),
      onOpen: vi.fn(),
      onError: vi.fn(),
      onClose: vi.fn(),
    }
    let created: { endPoint: string; opts: unknown } | undefined
    const FakeSocket = function (this: unknown, endPoint: string, opts: unknown) {
      created = { endPoint, opts }
      return socket
    } as unknown as typeof Socket

    const live = phoenixTransport(TEST_KEY, FakeSocket)
    expect(created).toEqual({ endPoint: '/socket', opts: { authToken: TEST_KEY } })

    const onNotice = vi.fn()
    live.join('dashboard:deliveries', onNotice)
    expect(socket.channel).toHaveBeenCalledWith('dashboard:deliveries')
    expect(channel.join).toHaveBeenCalled()
    const [, forward] = channel.on.mock.calls.find(([name]) => name === 'delivery_changed')!
    forward({ id: 'd1', status: 'failed' })
    expect(onNotice).toHaveBeenCalledWith('delivery_changed', { id: 'd1', status: 'failed' })

    const onStatus = vi.fn()
    live.onStatus(onStatus)
    socket.onError.mock.calls[0]![0]()
    socket.onOpen.mock.calls[0]![0]()
    expect(onStatus.mock.calls).toEqual([['reconnecting'], ['live']])

    live.connect()
    live.disconnect()
    expect(socket.connect).toHaveBeenCalled()
    expect(socket.disconnect).toHaveBeenCalled()
  })
})
