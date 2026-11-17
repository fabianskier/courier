import { setupServer } from 'msw/node'
import { afterAll, afterEach, beforeAll } from 'vitest'

// The network boundary of every test: requests without a handler fail.
export const server = setupServer()

// Call at the top of a test file to start, reset and stop the server there.
// (Not named `use…`: the linter would take it for a React hook.)
export function setupApiServer() {
  beforeAll(() => server.listen({ onUnhandledFrame: 'error' }))
  afterEach(() => server.resetHandlers())
  afterAll(() => server.close())
  return server
}
