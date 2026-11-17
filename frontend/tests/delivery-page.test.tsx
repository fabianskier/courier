import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { DeliveryDetail } from '@/lib/api/types'
import { formatDateTime } from '@/lib/format'
import { attemptFixture, deliveryDetailFixture } from './support/delivery-detail-fixtures'
import { endpointFixture, pageOf } from './support/event-fixtures'
import { errorFixture } from './support/fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()
const hook = endpointFixture('https://acme.test/hooks')

// Answers `GET /deliveries/:id` with these deliveries, and `404` for any other id.
const serveDeliveries = (...deliveries: DeliveryDetail[]) =>
  server.use(
    http.get('*/api/v1/deliveries/:id', ({ params }) => {
      const found = deliveries.find((d) => d.id === params.id)
      return found
        ? HttpResponse.json({ data: found })
        : HttpResponse.json(errorFixture('not_found', 'Not found.'), { status: 404 })
    }),
  )

beforeEach(() => {
  signIn()
  server.use(http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([hook]))))
})

const attempts = () => screen.findByRole('list', { name: 'Attempts' })
const entries = async () => within(await attempts()).getAllByRole('listitem')

describe('Requirement: Delivery page', () => {
  it('Scenario: Pending delivery', async () => {
    const delivery = deliveryDetailFixture({
      status: 'pending',
      endpoint_id: hook.id,
      completed_at: null,
      next_attempt_at: '2026-11-01T10:05:00Z',
      attempts: [attemptFixture({ response_status: 503 })],
    })
    serveDeliveries(delivery)
    renderDashboard(`/deliveries/${delivery.id}`)

    expect(await screen.findByText('This delivery is pending.')).toBeInTheDocument()
    expect(
      screen.getByText(`Next attempt due ${formatDateTime(delivery.next_attempt_at)}.`),
    ).toBeInTheDocument()
    // The summary: status, event link, endpoint URL, times and actor.
    expect(await screen.findByText(hook.url)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'payment.succeeded' })).toHaveAttribute(
      'href',
      `/events/${delivery.event_id}`,
    )
    expect(screen.getByText(formatDateTime(delivery.inserted_at))).toBeInTheDocument()
    expect(screen.getByText(formatDateTime(delivery.window_ends_at))).toBeInTheDocument()
    expect(screen.getByText('system')).toBeInTheDocument()
    expect(screen.getAllByText('pending').length).toBeGreaterThan(0)
  })

  it('Scenario: Skipped delivery', async () => {
    const delivery = deliveryDetailFixture({ status: 'skipped', attempts: [] })
    serveDeliveries(delivery)
    renderDashboard(`/deliveries/${delivery.id}`)

    expect(
      await screen.findByText("The endpoint's event filter excluded this event."),
    ).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: 'Attempts' })).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Attempts' })).not.toBeInTheDocument()
  })

  it('Scenario: Unknown delivery', async () => {
    serveDeliveries()
    renderDashboard('/deliveries/00000000-0000-4000-8000-00000000dead')

    expect(await screen.findByRole('heading', { name: 'Delivery not found' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to the deliveries' })).toHaveAttribute(
      'href',
      '/deliveries',
    )
  })
})

describe('Requirement: Attempt timeline', () => {
  it('Scenario: Failed then succeeded', async () => {
    const delivery = deliveryDetailFixture({
      status: 'succeeded',
      attempt_count: 2,
      attempts: [
        attemptFixture({
          number: 1,
          started_at: '2026-11-01T10:00:00Z',
          duration_ms: 812,
          response_status: 500,
          response_body: 'boom',
        }),
        attemptFixture({
          number: 2,
          started_at: '2026-11-01T10:00:30Z',
          duration_ms: 95,
          response_status: 200,
        }),
      ],
    })
    serveDeliveries(delivery)
    renderDashboard(`/deliveries/${delivery.id}`)

    const [first, second] = await entries()
    expect(first).toHaveTextContent('Attempt 1')
    expect(first).toHaveTextContent(`${formatDateTime('2026-11-01T10:00:00Z')} · 812 ms`)
    expect(first).toHaveTextContent('Status code 500')
    expect(second).toHaveTextContent('Attempt 2')
    expect(second).toHaveTextContent(`${formatDateTime('2026-11-01T10:00:30Z')} · 95 ms`)
    expect(second).toHaveTextContent('Status code 200')
    expect(screen.getByText('succeeded')).toBeInTheDocument()
  })

  it('Scenario: Attempt without a response', async () => {
    const delivery = deliveryDetailFixture({
      status: 'failed',
      attempts: [attemptFixture({ response_status: null, response_body: null, error: 'timeout' })],
    })
    serveDeliveries(delivery)
    renderDashboard(`/deliveries/${delivery.id}`)

    const [entry] = await entries()
    expect(entry).toHaveTextContent('Error timeout')
    expect(entry).not.toHaveTextContent('Status code')
  })

  it('Scenario: Long response body shortened', async () => {
    const body = 'a'.repeat(500) + 'b'.repeat(1500)
    const delivery = deliveryDetailFixture({
      attempts: [attemptFixture({ response_status: 502, response_body: body })],
    })
    serveDeliveries(delivery)
    const user = userEvent.setup()
    renderDashboard(`/deliveries/${delivery.id}`)

    const [entry] = await entries()
    const shown = within(entry!).getByLabelText('Response body')
    expect(shown.textContent).toContain('a'.repeat(500))
    expect(shown.textContent).not.toContain('b')

    await user.click(within(entry!).getByRole('button', { name: 'Show more' }))
    expect(within(entry!).getByLabelText('Response body')).toHaveTextContent(body)
  })
})

describe('Requirement: Resend links', () => {
  it('Scenario: Delivery and its resend linked', async () => {
    const original = deliveryDetailFixture({ status: 'failed' })
    const resend = deliveryDetailFixture({
      resend_of_id: original.id,
      triggered_by: 'api_key:demo',
      inserted_at: '2026-11-02T09:00:00Z',
    })
    original.resends = [
      {
        id: resend.id,
        status: resend.status,
        triggered_by: resend.triggered_by,
        inserted_at: resend.inserted_at,
      },
    ]
    serveDeliveries(original, resend)
    const user = userEvent.setup()
    renderDashboard(`/deliveries/${original.id}`)

    const resends = await screen.findByRole('list', { name: 'Resends' })
    const [item] = within(resends).getAllByRole('listitem')
    expect(item).toHaveTextContent('api_key:demo')
    expect(item).toHaveTextContent(formatDateTime(resend.inserted_at))
    expect(item).toHaveTextContent('succeeded')
    const toResend = within(item!).getByRole('link', { name: `Delivery ${resend.id.slice(0, 8)}` })
    expect(toResend).toHaveAttribute('href', `/deliveries/${resend.id}`)

    await user.click(toResend)
    expect(
      await screen.findByRole('heading', { name: `Delivery ${resend.id.slice(0, 8)}` }),
    ).toBeInTheDocument()
    expect(
      screen.getByRole('link', { name: `Delivery ${original.id.slice(0, 8)}` }),
    ).toHaveAttribute('href', `/deliveries/${original.id}`)
  })
})
