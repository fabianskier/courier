import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { Endpoint, MerchantDetail } from '@/lib/api/types'
import { formatDateTime } from '@/lib/format'
import { endpointFixture, pageOf } from './support/event-fixtures'
import { errorFixture } from './support/fixtures'
import { merchantDetailFixture } from './support/merchant-fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()

type Request = { method: string; path: string; search: string; body: unknown }

// An in-memory merchants API: list, show, create and update, plus the
// endpoints list filtered by `merchant_id`. Records every request it answers.
function serveMerchants(merchants: MerchantDetail[], endpoints: Endpoint[] = []) {
  const requests: Request[] = []
  const record = async (request: globalThis.Request) => {
    const url = new URL(request.url)
    const body = request.method === 'GET' ? null : await request.json()
    requests.push({ method: request.method, path: url.pathname, search: url.search, body })
    return body as Partial<MerchantDetail>
  }
  const notFound = () => HttpResponse.json(errorFixture('not_found', 'Not found.'), { status: 404 })

  server.use(
    http.get('*/api/v1/merchants', async ({ request }) => {
      await record(request)
      return HttpResponse.json(pageOf(merchants))
    }),
    http.get('*/api/v1/merchants/:id', async ({ request, params }) => {
      await record(request)
      const found = merchants.find((m) => m.id === params.id)
      return found ? HttpResponse.json({ data: found }) : notFound()
    }),
    http.post('*/api/v1/merchants', async ({ request }) => {
      const body = await record(request)
      const created = merchantDetailFixture({ name: body.name })
      merchants.unshift(created)
      return HttpResponse.json({ data: created }, { status: 201 })
    }),
    http.patch('*/api/v1/merchants/:id', async ({ request, params }) => {
      const body = await record(request)
      const index = merchants.findIndex((m) => m.id === params.id)
      if (index < 0) return notFound()
      merchants[index] = { ...merchants[index], ...body }
      return HttpResponse.json({ data: merchants[index] })
    }),
    http.get('*/api/v1/endpoints', async ({ request }) => {
      await record(request)
      const merchantId = new URL(request.url).searchParams.get('merchant_id')
      return HttpResponse.json(pageOf(endpoints.filter((e) => e.merchant_id === merchantId)))
    }),
  )
  return requests
}

const sent = (requests: Request[], method: string) => requests.filter((r) => r.method === method)

beforeEach(() => signIn(['read', 'write']))

describe('Requirement: Merchants list and page', () => {
  it('Scenario: Merchants listed', async () => {
    const acme = merchantDetailFixture({ name: 'Acme', inserted_at: '2026-11-02T08:30:00Z' })
    const harbor = merchantDetailFixture({ name: 'Harbor', enabled: false })
    serveMerchants([acme, harbor])
    renderDashboard('/merchants')

    const table = await screen.findByRole('table')
    const rows = within(table).getAllByRole('row').slice(1)
    expect(rows).toHaveLength(2)

    const acmeRow = within(rows[0])
    expect(acmeRow.getByRole('link', { name: 'Acme' })).toHaveAttribute(
      'href',
      `/merchants/${acme.id}`,
    )
    expect(acmeRow.getByText('Enabled')).toBeInTheDocument()
    expect(acmeRow.getByText(formatDateTime(acme.inserted_at))).toBeInTheDocument()

    const harborRow = within(rows[1])
    expect(harborRow.getByRole('link', { name: 'Harbor' })).toHaveAttribute(
      'href',
      `/merchants/${harbor.id}`,
    )
    expect(harborRow.getByText('Disabled')).toBeInTheDocument()

    const nav = screen.getByRole('navigation', { name: 'Dashboard' })
    expect(within(nav).getByRole('link', { name: 'Merchants' })).toHaveAttribute(
      'href',
      '/merchants',
    )
  })

  it('Scenario: Merchant with its endpoints', async () => {
    const acme = merchantDetailFixture({ name: 'Acme' })
    const first = { ...endpointFixture('https://acme.test/hooks/a'), merchant_id: acme.id }
    const second = { ...endpointFixture('https://acme.test/hooks/b'), merchant_id: acme.id }
    const other = endpointFixture('https://other.test/hooks')
    const requests = serveMerchants([acme], [first, second, other])
    renderDashboard(`/merchants/${acme.id}`)

    expect(await screen.findByRole('heading', { name: 'Acme' })).toBeInTheDocument()
    expect(screen.getByText('Enabled')).toBeInTheDocument()

    const list = await screen.findByRole('list', { name: 'Endpoints' })
    expect(within(list).getByText(first.url)).toBeInTheDocument()
    expect(within(list).getByText(second.url)).toBeInTheDocument()
    expect(within(list).queryByText(other.url)).not.toBeInTheDocument()

    const endpointRequest = requests.find((r) => r.path === '/api/v1/endpoints')
    expect(new URLSearchParams(endpointRequest?.search).get('merchant_id')).toBe(acme.id)
  })

  it('Scenario: Unknown merchant', async () => {
    serveMerchants([])
    renderDashboard('/merchants/missing')

    expect(await screen.findByRole('heading', { name: 'Merchant not found' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to the merchants' })).toHaveAttribute(
      'href',
      '/merchants',
    )
  })
})

describe('Requirement: Create and edit merchants', () => {
  it('Scenario: Merchant created', async () => {
    const requests = serveMerchants([merchantDetailFixture({ name: 'Harbor' })])
    const { router } = renderDashboard('/merchants')

    await userEvent.click(await screen.findByRole('button', { name: 'New merchant' }))
    const dialog = await screen.findByRole('dialog')
    await userEvent.type(within(dialog).getByLabelText('Name'), 'Acme')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create merchant' }))

    expect(await screen.findByRole('heading', { name: 'Acme' })).toBeInTheDocument()
    const posts = sent(requests, 'POST')
    expect(posts).toEqual([
      expect.objectContaining({ path: '/api/v1/merchants', body: { name: 'Acme' } }),
    ])
    await waitFor(() => expect(router.state.location.pathname).toMatch(/^\/merchants\/m\d{7}-/))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('Scenario: Merchant disabled', async () => {
    const acme = merchantDetailFixture({ name: 'Acme' })
    const requests = serveMerchants([acme])
    renderDashboard(`/merchants/${acme.id}`)

    await userEvent.click(await screen.findByRole('button', { name: 'Disable merchant' }))
    const dialog = await screen.findByRole('dialog')
    expect(sent(requests, 'PATCH')).toEqual([])
    await userEvent.click(within(dialog).getByRole('button', { name: 'Disable' }))

    expect(await screen.findByText('Disabled')).toBeInTheDocument()
    expect(sent(requests, 'PATCH')).toEqual([
      expect.objectContaining({ path: `/api/v1/merchants/${acme.id}`, body: { enabled: false } }),
    ])
    expect(screen.getByRole('button', { name: 'Enable merchant' })).toBeInTheDocument()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('Scenario: Invalid merchant name', async () => {
    const requests = serveMerchants([])
    server.use(
      http.post('*/api/v1/merchants', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'The request is invalid.',
              details: { name: ['should be at most 255 character(s)'] },
            },
          },
          { status: 422 },
        ),
      ),
    )
    const { router } = renderDashboard('/merchants')

    await userEvent.click(await screen.findByRole('button', { name: 'New merchant' }))
    const dialog = await screen.findByRole('dialog')
    const name = within(dialog).getByLabelText('Name')
    await userEvent.type(name, 'Too long')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create merchant' }))

    expect(
      await within(dialog).findByText('should be at most 255 character(s)'),
    ).toBeInTheDocument()
    expect(name).toHaveAttribute('aria-invalid', 'true')
    expect(name).toHaveValue('Too long')
    expect(router.state.location.pathname).toBe('/merchants')
    expect(requests.some((r) => r.path.startsWith('/api/v1/merchants/'))).toBe(false)
  })

  it('renames a merchant and enables a disabled one without a confirmation', async () => {
    const acme = merchantDetailFixture({ name: 'Acme', enabled: false })
    const requests = serveMerchants([acme])
    renderDashboard(`/merchants/${acme.id}`)

    const name = await screen.findByLabelText('Name')
    await userEvent.clear(name)
    await userEvent.type(name, 'Acme Shop')
    await userEvent.click(screen.getByRole('button', { name: 'Rename' }))
    expect(await screen.findByRole('heading', { name: 'Acme Shop' })).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Enable merchant' }))
    expect(await screen.findByRole('button', { name: 'Disable merchant' })).toBeInTheDocument()
    expect(sent(requests, 'PATCH').map((r) => r.body)).toEqual([
      { name: 'Acme Shop' },
      { enabled: true },
    ])
  })
})

describe('Requirement: Management needs the write scope', () => {
  it('Scenario: Read-only key (merchants pages)', async () => {
    signIn(['read'])
    const acme = merchantDetailFixture({ name: 'Acme' })
    serveMerchants([acme])
    const { unmount } = renderDashboard('/merchants')

    expect(await screen.findByRole('link', { name: 'Acme' })).toBeInTheDocument()
    expect(screen.getByText('Changes need the write scope.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'New merchant' })).not.toBeInTheDocument()
    unmount()

    renderDashboard(`/merchants/${acme.id}`)
    expect(await screen.findByRole('heading', { name: 'Acme' })).toBeInTheDocument()
    expect(screen.getByText('Changes need the write scope.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Disable|Enable|Rename/ })).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Name')).not.toBeInTheDocument()
  })
})
