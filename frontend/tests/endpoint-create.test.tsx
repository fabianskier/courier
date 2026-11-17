import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import type { EndpointDetail, MerchantDetail } from '@/lib/api/types'
import { endpointDetailFixture } from './support/endpoint-fixtures'
import { pageOf } from './support/event-fixtures'
import { merchantDetailFixture } from './support/merchant-fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()

const SECRET = 'whsec_test_8f2b1c9d4e7a'

type Created = { body: Record<string, unknown> }

// An in-memory endpoints API for creation: the merchants lookup, the
// endpoints list, one endpoint and `POST /endpoints`, which answers with the
// new endpoint and `SECRET`, or with `failure` when given.
function serveCreation(merchants: MerchantDetail[], failure?: () => Response) {
  const endpoints: EndpointDetail[] = []
  const posts: Created[] = []
  server.use(
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf(merchants))),
    http.get('*/api/v1/merchants/:id', ({ params }) =>
      HttpResponse.json({ data: merchants.find((m) => m.id === params.id) }),
    ),
    http.get('*/api/v1/endpoints', () => HttpResponse.json(pageOf(endpoints))),
    http.get('*/api/v1/endpoints/:id', ({ params }) =>
      HttpResponse.json({ data: endpoints.find((e) => e.id === params.id) }),
    ),
    http.post('*/api/v1/endpoints', async ({ request }) => {
      const body = (await request.json()) as Record<string, unknown>
      posts.push({ body })
      if (failure) return failure()
      const endpoint = endpointDetailFixture(body as Partial<EndpointDetail>)
      endpoints.push(endpoint)
      return HttpResponse.json({ data: { ...endpoint, secret: SECRET } }, { status: 201 })
    }),
  )
  return posts
}

const acme = merchantDetailFixture({ name: 'Acme' })
const harbor = merchantDetailFixture({ name: 'Harbor' })

// Radix Select uses pointer capture and scrolling, which jsdom lacks.
const stubs = { hasPointerCapture: () => false, scrollIntoView: () => {} }
beforeAll(() => void Object.assign(Element.prototype, stubs))

beforeEach(() => signIn(['read', 'write']))

const fillUrl = async (url: string) => {
  const field = await screen.findByLabelText('URL')
  await userEvent.clear(field)
  await userEvent.type(field, url)
}

describe('Requirement: Create endpoints', () => {
  it('Scenario: Endpoint created', async () => {
    const posts = serveCreation([acme, harbor])
    renderDashboard('/endpoints/new')

    await userEvent.click(await screen.findByLabelText('Merchant'))
    await userEvent.click(await screen.findByRole('option', { name: 'Harbor' }))
    await fillUrl('https://harbor.test/hooks')
    await userEvent.type(screen.getByLabelText('Event types'), 'payment.*, refund.created')
    await userEvent.click(screen.getByRole('button', { name: 'Create endpoint' }))

    await waitFor(() => expect(posts).toHaveLength(1))
    expect(posts[0].body).toEqual({
      merchant_id: harbor.id,
      url: 'https://harbor.test/hooks',
      event_types: ['payment.*', 'refund.created'],
      // The API's defaults, left unchanged.
      retry_window_seconds: 86_400,
      retry_on_4xx: false,
      max_concurrency: 10,
    })
  })

  it('sends the retry window in seconds and the other settings as entered', async () => {
    const posts = serveCreation([acme])
    renderDashboard(`/endpoints/new?merchant_id=${acme.id}`)

    await fillUrl('https://acme.test/hooks')
    await userEvent.type(screen.getByLabelText('Description'), 'Orders')
    const hours = screen.getByLabelText('Retry window (hours)')
    await userEvent.clear(hours)
    await userEvent.type(hours, '1.5')
    const concurrency = screen.getByLabelText('Concurrency')
    await userEvent.clear(concurrency)
    await userEvent.type(concurrency, '4')
    await userEvent.click(screen.getByRole('checkbox', { name: 'Retry on 4xx' }))
    await userEvent.click(screen.getByRole('button', { name: 'Create endpoint' }))

    await waitFor(() => expect(posts).toHaveLength(1))
    expect(posts[0].body).toEqual({
      merchant_id: acme.id,
      url: 'https://acme.test/hooks',
      description: 'Orders',
      event_types: [],
      retry_window_seconds: 5_400,
      retry_on_4xx: true,
      max_concurrency: 4,
    })
  })

  it('Scenario: Unsafe URL rejected', async () => {
    const message = 'must not point to a private or loopback address'
    const posts = serveCreation([acme], () =>
      HttpResponse.json(
        { error: { code: 'invalid', message: 'Invalid endpoint.', details: { url: [message] } } },
        { status: 422 },
      ),
    )
    const { router } = renderDashboard(`/endpoints/new?merchant_id=${acme.id}`)

    await fillUrl('http://127.0.0.1/hooks')
    await userEvent.type(screen.getByLabelText('Event types'), 'payment.*')
    await userEvent.click(screen.getByRole('button', { name: 'Create endpoint' }))

    expect(await screen.findByText(message)).toBeInTheDocument()
    expect(posts).toHaveLength(1)
    const url = screen.getByLabelText('URL')
    expect(url).toHaveAttribute('aria-invalid', 'true')
    expect(url).toHaveValue('http://127.0.0.1/hooks')
    expect(screen.getByLabelText('Event types')).toHaveValue('payment.*')
    expect(router.state.location.pathname).toBe('/endpoints/new')
    expect(screen.queryByLabelText('Signing secret')).not.toBeInTheDocument()
  })

  it('shows the retry window error from the API on the hours field', async () => {
    const message = 'must be less than or equal to 86400'
    serveCreation([acme], () =>
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
    renderDashboard(`/endpoints/new?merchant_id=${acme.id}`)

    await fillUrl('https://acme.test/hooks')
    const hours = screen.getByLabelText('Retry window (hours)')
    await userEvent.clear(hours)
    await userEvent.type(hours, '48')
    await userEvent.click(screen.getByRole('button', { name: 'Create endpoint' }))

    expect(await screen.findByText(message)).toBeInTheDocument()
    expect(screen.getByLabelText('Retry window (hours)')).toHaveAttribute('aria-invalid', 'true')
  })

  it('offers "New endpoint" on the merchant page with the merchant preselected', async () => {
    serveCreation([acme, harbor])
    const { router } = renderDashboard(`/merchants/${harbor.id}`)

    const link = await screen.findByRole('link', { name: 'New endpoint' })
    expect(link).toHaveAttribute('href', `/endpoints/new?merchant_id=${harbor.id}`)
    await userEvent.click(link)

    await waitFor(() => expect(router.state.location.pathname).toBe('/endpoints/new'))
    expect(await screen.findByLabelText('Merchant')).toHaveTextContent('Harbor')
  })

  it('shows the write scope note instead of the form to a read key', async () => {
    signIn(['read'])
    serveCreation([acme])
    renderDashboard(`/endpoints/new?merchant_id=${acme.id}`)

    expect(await screen.findByText('Changes need the write scope.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Create endpoint' })).not.toBeInTheDocument()
  })
})

// Creates an endpoint for Acme from the form and waits for its secret.
async function createForAcme() {
  await fillUrl('https://acme.test/hooks')
  await userEvent.click(screen.getByRole('button', { name: 'Create endpoint' }))
  return screen.findByLabelText('Signing secret')
}

describe('Requirement: Secret shown once', () => {
  it('Scenario: Secret after creation', async () => {
    serveCreation([acme])
    const { router } = renderDashboard(`/endpoints/new?merchant_id=${acme.id}`)
    const user = userEvent.setup()
    const writeText = vi.spyOn(navigator.clipboard, 'writeText')

    const secret = await createForAcme()
    expect(secret).toHaveValue(SECRET)
    expect(secret).toHaveAttribute('readonly')
    expect(
      screen.getByText('This secret will not be shown again. Store it now.'),
    ).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Create endpoint' })).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Copy' }))
    expect(writeText).toHaveBeenCalledWith(SECRET)

    await user.click(screen.getByRole('button', { name: 'Continue to the endpoint' }))
    expect(await screen.findByRole('heading', { name: 'https://acme.test/hooks' })).toBeVisible()
    expect(router.state.location.pathname).toMatch(/^\/endpoints\/e/)
    expect(document.body).not.toHaveTextContent(SECRET)
    expect(screen.queryByDisplayValue(SECRET)).not.toBeInTheDocument()

    // Going back opens an empty form: the secret cannot be recovered.
    router.history.back()
    expect(await screen.findByRole('button', { name: 'Create endpoint' })).toBeInTheDocument()
    expect(screen.queryByDisplayValue(SECRET)).not.toBeInTheDocument()
    expect(document.body).not.toHaveTextContent(SECRET)
  })

  it('Scenario: Secret kept out of storage', async () => {
    serveCreation([acme])
    const { router, queryClient } = renderDashboard(`/endpoints/new?merchant_id=${acme.id}`)

    expect(await createForAcme()).toHaveValue(SECRET)
    // The new endpoint (without its secret) is cached for its page.
    await waitFor(() =>
      expect(
        queryClient.getQueryCache().findAll({ queryKey: ['endpoints', 'detail'] }),
      ).toHaveLength(1),
    )

    const queries = queryClient.getQueryCache().getAll()
    const mutations = queryClient.getMutationCache().getAll()
    expect(mutations.length).toBeGreaterThan(0)
    const cached = JSON.stringify([
      queries.map((q) => ({ key: q.queryKey, state: q.state })),
      mutations.map((m) => m.state),
    ])
    expect(cached).not.toContain(SECRET)

    const stored = (storage: Storage) =>
      Object.keys(storage).map((key) => `${key}=${storage.getItem(key)}`)
    expect(stored(window.sessionStorage).join('\n')).not.toContain(SECRET)
    expect(stored(window.localStorage).join('\n')).not.toContain(SECRET)
    expect(window.location.href).not.toContain(SECRET)
    expect(router.state.location.href).not.toContain(SECRET)
  })
})
