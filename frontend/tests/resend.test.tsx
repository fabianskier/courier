import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { DeliveryDetail } from '@/lib/api/types'
import { shortId } from '@/lib/format'
import { deliveryDetailFixture } from './support/delivery-detail-fixtures'
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

// Counts `POST /deliveries/:id/resend` and answers each with `respond`.
const serveResend = (respond: (id: string) => Response) => {
  const calls: string[] = []
  server.use(
    http.post('*/api/v1/deliveries/:id/resend', ({ params }) => {
      calls.push(String(params.id))
      return respond(String(params.id))
    }),
  )
  return calls
}

const failed = () =>
  deliveryDetailFixture({ id: 'dlv-failed', status: 'failed', endpoint_id: hook.id })

beforeEach(() => {
  server.use(http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([hook]))))
})

const openDialog = async () => {
  await userEvent.click(await screen.findByRole('button', { name: 'Resend' }))
  return screen.findByRole('dialog')
}

describe('Requirement: Resend with confirmation', () => {
  it('Scenario: Resend confirmed', async () => {
    signIn(['read', 'write'])
    const original = failed()
    const resend = deliveryDetailFixture({
      id: 'dlv-resend',
      status: 'pending',
      endpoint_id: hook.id,
      resend_of_id: original.id,
      triggered_by: 'api_key:demo',
      attempts: [],
    })
    serveDeliveries(original, resend)
    const calls = serveResend(() => HttpResponse.json({ data: resend }, { status: 202 }))
    const { router } = renderDashboard(`/deliveries/${original.id}`)

    const dialog = await openDialog()
    expect(await within(dialog).findByText(hook.url)).toBeInTheDocument()
    expect(calls).toEqual([])

    await userEvent.click(within(dialog).getByRole('button', { name: 'Resend' }))

    expect(await screen.findByText('Resend created')).toBeInTheDocument()
    await waitFor(() => expect(router.state.location.pathname).toBe(`/deliveries/${resend.id}`))
    expect(
      await screen.findByRole('heading', { name: `Delivery ${shortId(resend.id)}` }),
    ).toBeInTheDocument()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(calls).toEqual([original.id])
  })

  it('Scenario: Resend cancelled', async () => {
    signIn(['read', 'write'])
    const original = failed()
    serveDeliveries(original)
    const calls = serveResend(() => HttpResponse.json({}, { status: 500 }))
    const { router } = renderDashboard(`/deliveries/${original.id}`)

    const dialog = await openDialog()
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }))

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(calls).toEqual([])
    expect(router.state.location.pathname).toBe(`/deliveries/${original.id}`)
  })

  it('Scenario: Resend refused', async () => {
    signIn(['read', 'write'])
    const original = failed()
    serveDeliveries(original)
    const message = 'The endpoint is disabled; enable it before resending.'
    const calls = serveResend(() =>
      HttpResponse.json(errorFixture('endpoint_disabled', message), { status: 422 }),
    )
    const { router } = renderDashboard(`/deliveries/${original.id}`)

    const dialog = await openDialog()
    await userEvent.click(within(dialog).getByRole('button', { name: 'Resend' }))

    expect(await within(dialog).findByText(message)).toBeInTheDocument()
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(router.state.location.pathname).toBe(`/deliveries/${original.id}`)
    expect(calls).toEqual([original.id])
  })
})

describe('Requirement: Resend only when allowed', () => {
  it('Scenario: Read-only key', async () => {
    signIn(['read'])
    const original = failed()
    serveDeliveries(original)
    renderDashboard(`/deliveries/${original.id}`)

    const button = await screen.findByRole('button', { name: 'Resend' })
    expect(button).toBeDisabled()
    expect(button).toHaveAccessibleDescription('Resending needs the write scope.')
    expect(screen.getByText('Resending needs the write scope.')).toBeVisible()
  })

  it('Scenario: No resend while pending', async () => {
    signIn(['read', 'write'])
    const pending = deliveryDetailFixture({
      id: 'dlv-pending',
      status: 'pending',
      endpoint_id: hook.id,
      completed_at: null,
    })
    serveDeliveries(pending)
    renderDashboard(`/deliveries/${pending.id}`)

    expect(await screen.findByText('This delivery is pending.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Resend' })).not.toBeInTheDocument()
  })
})
