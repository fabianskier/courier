import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { EndpointDetail } from '@/lib/api/types'
import { formatDateTime } from '@/lib/format'
import { endpointDetailFixture } from './support/endpoint-fixtures'
import { pageOf } from './support/event-fixtures'
import { merchantDetailFixture } from './support/merchant-fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()

const SECRET = 'whsec_rotated_3c7d9e1f'
const EXPIRES_AT = '2026-11-18T12:00:00Z'

type Request = { method: string; path: string; body: unknown }

const acme = merchantDetailFixture({ name: 'Acme' })

// An in-memory endpoints API for one endpoint: the lookups, `GET`, `PATCH`
// (applied to the endpoint, or answered with `failure`) and `rotate_secret`.
function serveEndpoint(initial: Partial<EndpointDetail>, failure?: () => Response) {
  let endpoint = endpointDetailFixture({ merchant_id: acme.id, ...initial })
  const requests: Request[] = []
  server.use(
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([acme]))),
    http.get('*/api/v1/merchants/:id', () => HttpResponse.json({ data: acme })),
    http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf([endpoint]))),
    http.get('*/api/v1/endpoints/:id', () => HttpResponse.json({ data: endpoint })),
    http.patch('*/api/v1/endpoints/:id', async ({ request }) => {
      const body = (await request.json()) as Partial<EndpointDetail>
      requests.push({ method: 'PATCH', path: new URL(request.url).pathname, body })
      if (failure) return failure()
      endpoint = { ...endpoint, ...body, updated_at: new Date().toISOString() }
      return HttpResponse.json({ data: endpoint })
    }),
    http.post('*/api/v1/endpoints/:id/rotate_secret', ({ request }) => {
      requests.push({ method: 'POST', path: new URL(request.url).pathname, body: null })
      endpoint = { ...endpoint, previous_secret_expires_at: EXPIRES_AT, updated_at: EXPIRES_AT }
      return HttpResponse.json({ data: { ...endpoint, secret: SECRET } })
    }),
  )
  return { endpoint, requests }
}

beforeEach(() => signIn(['read', 'write']))

describe('Requirement: Edit, disable and rotate endpoints', () => {
  it('Scenario: Endpoint edited', async () => {
    const { endpoint, requests } = serveEndpoint({ event_types: ['payment.*'] })
    renderDashboard(`/endpoints/${endpoint.id}`)

    const input = await screen.findByRole('textbox', { name: 'Event types' })
    expect(input).toHaveValue('payment.*')
    await userEvent.clear(input)
    await userEvent.type(input, 'invoice.*')
    await userEvent.click(screen.getByRole('button', { name: 'Save changes' }))

    await waitFor(() => expect(requests).toHaveLength(1))
    expect(requests[0]).toEqual({
      method: 'PATCH',
      path: `/api/v1/endpoints/${endpoint.id}`,
      body: { event_types: ['invoice.*'] },
    })
    const filters = await screen.findByRole('list', { name: 'Event types' })
    await waitFor(() => expect(filters).toHaveTextContent('invoice.*'))
    expect(filters).not.toHaveTextContent('payment.*')
  })

  it('sends the retry window in seconds and shows API errors on their fields', async () => {
    const message = 'must be less than or equal to 86400'
    const { endpoint, requests } = serveEndpoint({}, () =>
      HttpResponse.json(
        {
          error: {
            code: 'invalid',
            message: 'Invalid endpoint.',
            details: { retry_window_seconds: [message] },
          },
        },
        { status: 422 },
      ),
    )
    renderDashboard(`/endpoints/${endpoint.id}`)

    const hours = await screen.findByLabelText('Retry window (hours)')
    expect(hours).toHaveValue(24)
    await userEvent.clear(hours)
    await userEvent.type(hours, '48')
    await userEvent.click(screen.getByRole('button', { name: 'Save changes' }))

    expect(await screen.findByText(message)).toBeInTheDocument()
    expect(requests[0].body).toEqual({ retry_window_seconds: 172_800 })
    expect(screen.getByLabelText('Retry window (hours)')).toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByLabelText('Retry window (hours)')).toHaveValue(48)
  })

  it('Scenario: Endpoint disabled', async () => {
    const { endpoint, requests } = serveEndpoint({ enabled: true })
    renderDashboard(`/endpoints/${endpoint.id}`)

    await userEvent.click(await screen.findByRole('button', { name: 'Disable endpoint' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Disable' }))

    await waitFor(() => expect(requests).toHaveLength(1))
    expect(requests[0]).toEqual({
      method: 'PATCH',
      path: `/api/v1/endpoints/${endpoint.id}`,
      body: { enabled: false },
    })
    expect(await screen.findByRole('button', { name: 'Enable endpoint' })).toBeInTheDocument()
    expect(screen.getByText('Disabled')).toBeInTheDocument()
  })

  it('enables a disabled endpoint without a confirmation', async () => {
    const { endpoint, requests } = serveEndpoint({ enabled: false })
    renderDashboard(`/endpoints/${endpoint.id}`)

    await userEvent.click(await screen.findByRole('button', { name: 'Enable endpoint' }))

    await waitFor(() => expect(requests).toHaveLength(1))
    expect(requests[0].body).toEqual({ enabled: true })
    expect(await screen.findByRole('button', { name: 'Disable endpoint' })).toBeInTheDocument()
  })

  it('Scenario: Secret rotated', async () => {
    const { endpoint, requests } = serveEndpoint({})
    const { queryClient } = renderDashboard(`/endpoints/${endpoint.id}`)
    const user = userEvent.setup()

    await user.click(await screen.findByRole('button', { name: 'Rotate secret' }))
    const dialog = await screen.findByRole('dialog')
    expect(dialog).toHaveTextContent('The previous secret keeps signing for 24 hours')
    expect(requests).toHaveLength(0)
    await user.click(within(dialog).getByRole('button', { name: 'Rotate' }))

    const secret = await within(dialog).findByLabelText('Signing secret')
    expect(secret).toHaveValue(SECRET)
    expect(
      within(dialog).getByText('This secret will not be shown again. Store it now.'),
    ).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: 'Copy' })).toBeInTheDocument()
    expect(requests).toEqual([
      { method: 'POST', path: `/api/v1/endpoints/${endpoint.id}/rotate_secret`, body: null },
    ])

    const cached = JSON.stringify([
      queryClient
        .getQueryCache()
        .getAll()
        .map((q) => q.state),
      queryClient
        .getMutationCache()
        .getAll()
        .map((m) => m.state),
    ])
    expect(cached).not.toContain(SECRET)

    await user.click(within(dialog).getByRole('button', { name: 'Done' }))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(await screen.findByText(`Signs until ${formatDateTime(EXPIRES_AT)}`)).toBeInTheDocument()
    expect(document.body).not.toHaveTextContent(SECRET)
    expect(screen.queryByDisplayValue(SECRET)).not.toBeInTheDocument()
    expect(requests).toHaveLength(1)
  })

  it('rotates nothing when the confirmation is cancelled', async () => {
    const { endpoint, requests } = serveEndpoint({})
    renderDashboard(`/endpoints/${endpoint.id}`)

    await userEvent.click(await screen.findByRole('button', { name: 'Rotate secret' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }))

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(requests).toHaveLength(0)
  })
})

describe('Requirement: Management needs the write scope', () => {
  it('Scenario: Read-only key', async () => {
    signIn(['read'])
    const { endpoint } = serveEndpoint({ event_types: ['payment.*'] })
    const actions = /Disable|Enable|Rotate|Save|New endpoint|New merchant|Rename/

    const endpointPage = renderDashboard(`/endpoints/${endpoint.id}`)
    expect(await screen.findByRole('heading', { name: endpoint.url })).toBeInTheDocument()
    expect(screen.getByText('Changes need the write scope.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: actions })).not.toBeInTheDocument()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    endpointPage.unmount()

    const merchantsPage = renderDashboard('/merchants')
    expect(await screen.findByRole('link', { name: 'Acme' })).toBeInTheDocument()
    expect(screen.getByText('Changes need the write scope.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: actions })).not.toBeInTheDocument()
    merchantsPage.unmount()

    renderDashboard('/endpoints')
    expect(await screen.findByRole('link', { name: endpoint.url })).toBeInTheDocument()
    expect(screen.getByText('Changes need the write scope.')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'New endpoint' })).not.toBeInTheDocument()
  })

  it('offers "New endpoint" on the endpoints list to a write key', async () => {
    const { endpoint } = serveEndpoint({})
    renderDashboard('/endpoints')

    expect(await screen.findByRole('link', { name: endpoint.url })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'New endpoint' })).toHaveAttribute(
      'href',
      '/endpoints/new',
    )
    expect(screen.queryByText('Changes need the write scope.')).not.toBeInTheDocument()
  })
})
