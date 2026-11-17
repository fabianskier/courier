import { http, HttpResponse } from 'msw'
import { afterEach } from 'vitest'
import { installUnauthorizedHandler } from '@/features/auth/session'
import { renderApp } from '../render'
import { meFixture } from './fixtures'
import { server } from './server'

export const TEST_KEY = 'ck_test_secret_key'

afterEach(() => {
  window.sessionStorage.clear()
  window.localStorage.clear()
})

// Stores a key before `renderApp`, and answers `/me` for it with `scopes`.
export function signIn(scopes: string[] = ['read', 'write'], name = 'demo') {
  window.sessionStorage.setItem('courier.apiKey', TEST_KEY)
  server.use(http.get('*/api/v1/me', () => HttpResponse.json(meFixture({ name, scopes }))))
}

// `renderApp` with the app's `401` handling, as `main.tsx` installs it.
export function renderDashboard(path = '/') {
  const result = renderApp(path)
  installUnauthorizedHandler(result.router, result.queryClient)
  return result
}
