import { screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { renderApp } from './render'

// Smoke tests of the bootstrap: the router, the layout and the not-found page.
describe('App shell', () => {
  it('renders the overview at the root path', async () => {
    renderApp('/')

    expect(await screen.findByRole('heading', { name: 'Overview' })).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Main' })).toBeInTheDocument()
  })

  it('shows a not-found page for an unknown path', async () => {
    renderApp('/no-such-page')

    expect(await screen.findByRole('heading', { name: 'Page not found' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to the overview' })).toHaveAttribute('href', '/')
  })
})
