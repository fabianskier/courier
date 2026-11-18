import { screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { setupApiServer } from './support/server'
import { renderDashboard, signIn } from './support/session'

setupApiServer()

// The overview is outside the `_app` layout: after signing in it must still
// lead to every dashboard page, or the operator lands on a page with no way on.
describe('Overview after sign-in', () => {
  it('links to every dashboard page when a key is stored', async () => {
    signIn()
    renderDashboard('/')

    const pages = await screen.findByRole('list', { name: 'Dashboard pages' })
    const links = within(pages).getAllByRole('link')

    expect(links.map((link) => link.getAttribute('href'))).toEqual([
      '/events',
      '/deliveries',
      '/failed',
      '/endpoints',
      '/merchants',
    ])
    expect(screen.queryByRole('link', { name: 'Sign in' })).not.toBeInTheDocument()
  })

  it('offers only sign-in without a key', async () => {
    renderDashboard('/')

    expect(await screen.findByRole('link', { name: 'Sign in' })).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: 'Dashboard pages' })).not.toBeInTheDocument()
  })
})
