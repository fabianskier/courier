import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import { merchantFixture, pageOf } from './support/event-fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()

const acme = merchantFixture('Acme Supplies')
const harbor = merchantFixture('Harbor Outfitters')

// The `merchant_id` of every list request, `null` when absent. The shared
// lookups (`limit=100`) are not list requests.
let requested: Record<string, (string | null)[]>

const recordList = (path: string) =>
  http.get(`*/api/v1/${path}`, ({ request }) => {
    const params = new URL(request.url).searchParams
    if (!params.has('limit')) {
      ;(requested[path] ??= []).push(params.get('merchant_id'))
    }
    return HttpResponse.json(pageOf([]))
  })

beforeEach(() => {
  requested = {}
  server.use(
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([acme, harbor]))),
    recordList('deliveries'),
    recordList('events'),
    recordList('endpoints'),
  )
})

const listLinks = async () => {
  const nav = await screen.findByRole('navigation', { name: 'Dashboard' })
  const link = (name: string) => within(nav).getByRole('link', { name })
  return ['Events', 'Deliveries', 'Failed', 'Endpoints'].map((name) => link(name))
}

async function choose(name: string) {
  const user = userEvent.setup()
  await user.click(await screen.findByRole('button', { name: /^Viewing / }))
  await user.click(await screen.findByRole('menuitemradio', { name }))
}

describe('Requirement: Merchant switcher', () => {
  it('Scenario: Merchant chosen', async () => {
    signIn()
    const { router } = renderDashboard('/deliveries?status=failed')
    await waitFor(() => expect(requested.deliveries).toEqual([null]))

    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: 'Viewing All merchants' }))
    const options = await screen.findAllByRole('menuitemradio')
    expect(options.map((option) => option.textContent)).toEqual([
      'All merchants',
      'Acme Supplies',
      'Harbor Outfitters',
    ])
    await user.click(screen.getByRole('menuitemradio', { name: 'Harbor Outfitters' }))

    await waitFor(() => expect(requested.deliveries).toEqual([null, harbor.id]))
    expect(router.state.location.search).toEqual({ status: 'failed', merchant_id: harbor.id })
    expect(screen.getByRole('button', { name: 'Viewing Harbor Outfitters' })).toBeInTheDocument()

    for (const link of await listLinks()) {
      expect(new URL(link.getAttribute('href')!, 'http://x').searchParams.get('merchant_id')).toBe(
        harbor.id,
      )
    }
    const nav = screen.getByRole('navigation', { name: 'Dashboard' })
    expect(within(nav).getByRole('link', { name: 'Merchants' })).toHaveAttribute(
      'href',
      '/merchants',
    )
    expect(within(nav).getByRole('link', { name: 'Overview' })).toHaveAttribute('href', '/')
  })

  it('Scenario: Selection kept', async () => {
    signIn()
    const first = renderDashboard('/deliveries')
    await choose('Harbor Outfitters')
    expect(
      await screen.findByRole('button', { name: 'Viewing Harbor Outfitters' }),
    ).toBeInTheDocument()
    first.unmount()

    renderDashboard('/merchants')
    expect(
      await screen.findByRole('button', { name: 'Viewing Harbor Outfitters' }),
    ).toBeInTheDocument()
  })

  it('Scenario: All merchants', async () => {
    signIn()
    window.sessionStorage.setItem('courier.merchant', harbor.id)
    renderDashboard(`/events?merchant_id=${harbor.id}`)
    await waitFor(() => expect(requested.events).toEqual([harbor.id]))
    expect(
      await screen.findByRole('button', { name: 'Viewing Harbor Outfitters' }),
    ).toBeInTheDocument()

    await choose('All merchants')

    await waitFor(() => expect(requested.events).toEqual([harbor.id, null]))
    expect(screen.getByRole('button', { name: 'Viewing All merchants' })).toBeInTheDocument()
    expect(window.sessionStorage.getItem('courier.merchant')).toBeNull()
    expect((await listLinks()).map((link) => link.getAttribute('href'))).toEqual([
      '/events',
      '/deliveries',
      '/failed',
      '/endpoints',
    ])
  })
})
