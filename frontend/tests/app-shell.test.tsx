import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import { endpointFixture, merchantFixture, pageOf } from './support/event-fixtures'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

const server = setupApiServer()

beforeEach(() => {
  server.use(
    http.get('*/api/v1/deliveries', () => HttpResponse.json(pageOf([]))),
    http.get('*/api/v1/merchants', () => HttpResponse.json(pageOf([merchantFixture('Acme')]))),
    http.get('*/api/v1/endpoints', () =>
      HttpResponse.json(pageOf([endpointFixture('https://acme.test/a')])),
    ),
  )
})

const sidebar = () => document.querySelector('[data-slot="sidebar"]')
const hrefs = (links: HTMLElement[]) => links.map((link) => link.getAttribute('href'))

describe('Requirement: Sidebar layout', () => {
  it('Scenario: Sidebar on a data page', async () => {
    signIn(['read', 'write'], 'ops-admin')
    renderDashboard('/deliveries')

    const nav = await screen.findByRole('navigation', { name: 'Dashboard' })
    expect(within(nav).getByRole('link', { name: 'Overview' })).toHaveAttribute('href', '/')

    const activity = within(nav).getByRole('list', { name: 'Activity' })
    expect(hrefs(within(activity).getAllByRole('link'))).toEqual([
      '/events',
      '/deliveries',
      '/failed',
    ])
    const configuration = within(nav).getByRole('list', { name: 'Configuration' })
    expect(hrefs(within(configuration).getAllByRole('link'))).toEqual(['/endpoints', '/merchants'])

    for (const link of within(nav).getAllByRole('link')) {
      expect(link.querySelector('svg')).not.toBeNull()
    }
    const current = within(nav)
      .getAllByRole('link')
      .filter((link) => link.getAttribute('aria-current') === 'page')
    expect(current.map((link) => link.textContent)).toEqual(['Deliveries'])

    const keyInUse = screen.getByLabelText('Key in use')
    expect(keyInUse).toHaveTextContent('ops-admin')
    expect(keyInUse).toHaveTextContent('read')
    expect(keyInUse).toHaveTextContent('write')
    expect(screen.getByRole('button', { name: 'Sign out' })).toBeInTheDocument()

    const breadcrumb = screen.getByRole('navigation', { name: 'breadcrumb' })
    expect(within(breadcrumb).getByText('Deliveries')).toHaveAttribute('aria-current', 'page')
    expect(screen.getByText('Connecting…')).toHaveAttribute('role', 'status')
    expect(screen.queryByRole('navigation', { name: 'Main' })).not.toBeInTheDocument()
  })

  it('Scenario: Sidebar collapses', async () => {
    signIn()
    renderDashboard('/deliveries')
    const user = userEvent.setup()

    const toggle = await screen.findByRole('button', { name: 'Toggle sidebar' })
    expect(sidebar()).toHaveAttribute('data-state', 'expanded')

    await user.click(toggle)
    expect(sidebar()).toHaveAttribute('data-state', 'collapsed')
    expect(sidebar()).toHaveAttribute('data-collapsible', 'icon')

    await user.click(toggle)
    expect(sidebar()).toHaveAttribute('data-state', 'expanded')
  })

  it('Scenario: No sidebar without a key', async () => {
    const overview = renderDashboard('/')
    expect(await screen.findByRole('link', { name: 'Sign in' })).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Main' })).toBeInTheDocument()
    expect(sidebar()).toBeNull()
    expect(screen.queryByRole('navigation', { name: 'Dashboard' })).not.toBeInTheDocument()
    overview.unmount()

    renderDashboard('/sign-in')
    expect(await screen.findByLabelText('API key')).toBeInTheDocument()
    expect(sidebar()).toBeNull()
    expect(screen.queryByRole('navigation', { name: 'Dashboard' })).not.toBeInTheDocument()
  })

  it('shows the sidebar on the overview when a key is stored', async () => {
    signIn()
    renderDashboard('/')

    const nav = await screen.findByRole('navigation', { name: 'Dashboard' })
    expect(within(nav).getByRole('link', { name: 'Overview' })).toHaveAttribute(
      'aria-current',
      'page',
    )
    expect(sidebar()).not.toBeNull()
    expect(screen.getByRole('list', { name: 'Dashboard pages' })).toBeInTheDocument()
    expect(screen.queryByRole('navigation', { name: 'Main' })).not.toBeInTheDocument()
    expect(screen.getAllByRole('main')).toHaveLength(1)
  })
})
