import { render, screen, within } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import { LiveStatus } from '@/components/live-status'
import { deliveryFixture } from './support/delivery-fixtures'
import { degradedEndpointFixture, endpointDetailFixture } from './support/endpoint-fixtures'
import { endpointFixture, merchantFixture, pageOf } from './support/event-fixtures'
import { merchantDetailFixture } from './support/merchant-fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()

beforeEach(() => signIn())

// The badge whose text is `text`, inside `scope`.
const badgeIn = (scope: HTMLElement, text: string) =>
  within(scope).getByText(text).closest('[data-slot="badge"]') as HTMLElement

describe('Requirement: Status colors', () => {
  it('Scenario: Delivery status colors', async () => {
    const hook = endpointFixture('https://acme.test/hooks')
    const statuses = ['succeeded', 'failed', 'pending', 'skipped'] as const
    const deliveries = statuses.map((status) => deliveryFixture({ endpoint_id: hook.id, status }))
    server.use(
      http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([merchantFixture('Acme')]))),
      http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([hook]))),
      http.get('*/api/v1/deliveries', () => HttpResponse.json(pageOf(deliveries))),
    )
    renderDashboard('/deliveries')

    await screen.findByRole('link', { name: deliveries[0]!.id.slice(0, 8) })
    const rows = within(screen.getByRole('table')).getAllByRole('row').slice(1)
    const expected = ['success', 'destructive', 'warning', 'secondary']

    statuses.forEach((status, i) => {
      const badge = badgeIn(rows[i]!, status)
      expect(badge).toHaveAttribute('data-variant', expected[i])
      expect(badge).toHaveTextContent(status)
      expect(badge.querySelector('svg')).not.toBeNull()
    })
  })

  it('Scenario: Endpoint health colors', async () => {
    const acme = merchantDetailFixture({ name: 'Acme' })
    const healthy = endpointDetailFixture({ url: 'https://acme.test/ok', merchant_id: acme.id })
    const failing = degradedEndpointFixture(4, {
      url: 'https://acme.test/ko',
      merchant_id: acme.id,
    })
    server.use(
      http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([acme]))),
      http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([healthy, failing]))),
    )
    renderDashboard('/endpoints')

    const table = await screen.findByRole('table')
    const [first, second] = within(table).getAllByRole('row').slice(1)
    expect(badgeIn(first!, 'Healthy')).toHaveAttribute('data-variant', 'success')
    expect(badgeIn(second!, 'Degraded')).toHaveAttribute('data-variant', 'destructive')
  })

  it('shows the live status as success when live and warning while reconnecting', () => {
    const { rerender } = render(<LiveStatus status="live" />)
    expect(screen.getByRole('status').querySelector('svg')).toHaveClass('text-success')
    expect(screen.getByRole('status')).toHaveTextContent('Live')

    rerender(<LiveStatus status="reconnecting" />)
    expect(screen.getByRole('status').querySelector('svg')).toHaveClass('text-warning')
    expect(screen.getByRole('status')).toHaveTextContent('Reconnecting…')
  })
})
